defmodule Toon.Encoder.Core do
  @moduledoc false

  # Main encoding pipeline. Converts a normalized value tree into a TOON document string.
  #
  # Design decisions:
  # - normalize/1 returns ordered [{String.t(), term()}] pairs for objects and [term()] for
  #   arrays. The encoder distinguishes them by checking if the head element is a
  #   {binary_key, _} tuple.
  # - encode_value/3 is the external entry point called by Toon.encode/2.
  # - All internal helpers return String.t() directly (the iodata() wrapping is a thin
  #   layer — the public API converts via IO.iodata_to_binary/1).
  # - Empty objects (empty pair-list) encode to "" (no output); empty arrays encode to
  #   an inline form with zero length.

  alias Toon.StringUtils
  alias Toon.Encoder.{Normalize, Primitives, Replacer, Folding}

  @type opts :: keyword()

  # ---------------------------------------------------------------------------
  # Public entry point
  # ---------------------------------------------------------------------------

  @spec encode_value(term(), opts(), [String.t() | integer()]) :: iodata()
  def encode_value(input, opts, path) do
    replacer = Keyword.get(opts, :replacer)
    normalized = Normalize.normalize(input)

    # Apply replacer to the root value (key is "" for root)
    final =
      case Replacer.apply(normalized, replacer, "", path) do
        {:keep, v} -> v
        # Skipping the root is a no-op — there's nothing to omit it from
        :skip -> normalized
      end

    do_encode(final, opts, path, 0)
  end

  # encode_lines/2: returns a Stream of line binaries.
  # NOTE: unlike encode/2, encoding failures raise EncodeError during enumeration.
  @spec encode_lines(term(), opts()) :: Enumerable.t()
  def encode_lines(input, opts) do
    Stream.resource(
      fn ->
        result = encode_value(input, opts, [])
        IO.iodata_to_binary(result)
      end,
      fn
        nil ->
          {:halt, nil}

        text ->
          lines = String.split(text, "\n")
          {lines, nil}
      end,
      fn _ -> :ok end
    )
  end

  # ---------------------------------------------------------------------------
  # Core dispatch
  # ---------------------------------------------------------------------------

  # Primitives are delegated directly to Primitives module with the document delimiter
  defp do_encode(nil, _opts, _path, _depth), do: "null"
  defp do_encode(true, _opts, _path, _depth), do: "true"
  defp do_encode(false, _opts, _path, _depth), do: "false"
  defp do_encode(n, _opts, _path, _depth) when is_integer(n), do: Integer.to_string(n)

  defp do_encode(f, opts, _path, _depth) when is_float(f) do
    doc_delim = resolve_delimiter(Keyword.get(opts, :delimiter, :comma))
    Primitives.encode_primitive(f, doc_delim)
  end

  defp do_encode(s, opts, _path, _depth) when is_binary(s) do
    doc_delim = resolve_delimiter(Keyword.get(opts, :delimiter, :comma))
    Primitives.encode_primitive(s, doc_delim)
  end

  defp do_encode(pairs, opts, path, depth) when is_list(pairs) do
    case pairs do
      [] ->
        # Ambiguous empty — treat as empty object (no output)
        ""

      [{k, _} | _] when is_binary(k) ->
        # Object: ordered key-value pairs
        encode_object(pairs, opts, path, depth)

      _ ->
        # Array
        active_delim = resolve_delimiter(Keyword.get(opts, :delimiter, :comma))
        encode_array_standalone(pairs, opts, path, depth, active_delim)
    end
  end

  # ---------------------------------------------------------------------------
  # Object encoding
  # ---------------------------------------------------------------------------

  defp encode_object(pairs, opts, path, depth) do
    indent_size = Keyword.get(opts, :indent, 2)
    key_folding = Keyword.get(opts, :key_folding, :off)
    flatten_depth = Keyword.get(opts, :flatten_depth, :infinity)
    replacer = Keyword.get(opts, :replacer)
    doc_delim = resolve_delimiter(Keyword.get(opts, :delimiter, :comma))

    pairs
    |> Enum.flat_map(fn {k, v} ->
      # Apply key folding before replacer so the replacer sees the folded key
      {folded_key, folded_value} = Folding.fold(k, v, key_folding, flatten_depth, 0)
      new_path = path ++ [k]

      # Re-normalize the folded value in case folding exposed un-normalized data
      normalized_v = Normalize.normalize(folded_value)

      case Replacer.apply(normalized_v, replacer, k, new_path) do
        :skip ->
          []

        {:keep, final_v} ->
          line = encode_kv(folded_key, final_v, opts, new_path, depth, doc_delim, indent_size)

          if line == "" do
            []
          else
            [line]
          end
      end
    end)
    |> Enum.join("\n")
  end

  # ---------------------------------------------------------------------------
  # Key-value line encoding
  # ---------------------------------------------------------------------------

  defp encode_kv(key, value, opts, path, depth, doc_delim, indent_size) do
    prefix = String.duplicate(" ", depth * indent_size)
    encoded_key = encode_key(key)

    case value do
      nil ->
        "#{prefix}#{encoded_key}: null"

      true ->
        "#{prefix}#{encoded_key}: true"

      false ->
        "#{prefix}#{encoded_key}: false"

      n when is_integer(n) ->
        "#{prefix}#{encoded_key}: #{n}"

      f when is_float(f) ->
        "#{prefix}#{encoded_key}: #{Primitives.encode_primitive(f, doc_delim)}"

      s when is_binary(s) ->
        encoded_val = Primitives.encode_primitive(s, doc_delim)
        "#{prefix}#{encoded_key}: #{encoded_val}"

      [] ->
        # Empty array — use zero-length inline form
        delim_sym = delimiter_symbol(doc_delim)
        "#{prefix}#{encoded_key}[0#{delim_sym}]:"

      [{_, _} | _] = sub_pairs ->
        # Nested object: recurse with increased depth
        child_block = encode_object(sub_pairs, opts, path, depth + 1)

        if child_block == "" do
          "#{prefix}#{encoded_key}:"
        else
          "#{prefix}#{encoded_key}:\n#{child_block}"
        end

      list when is_list(list) ->
        encode_array_kv(encoded_key, list, opts, path, depth, doc_delim, indent_size, prefix)
    end
  end

  # ---------------------------------------------------------------------------
  # Array encoding (as a key-value entry)
  # ---------------------------------------------------------------------------

  defp encode_array_kv(encoded_key, list, opts, path, depth, doc_delim, indent_size, prefix) do
    n = length(list)
    delim_sym = delimiter_symbol(doc_delim)

    cond do
      all_primitives?(list) ->
        # Primitive array: key[N]: v1,v2,v3
        values = Enum.map(list, &Primitives.encode_primitive(&1, doc_delim))
        "#{prefix}#{encoded_key}[#{n}#{delim_sym}]: #{Enum.join(values, <<doc_delim>>)}"

      tabular?(list) ->
        # Tabular uniform array: key[N]{f1,f2}:\n  r1,r2
        encode_tabular_kv(
          encoded_key,
          list,
          doc_delim,
          indent_size,
          prefix,
          depth,
          n,
          delim_sym
        )

      true ->
        # Expanded list: key[N]:\n  - item
        encode_expanded_kv(
          encoded_key,
          list,
          opts,
          path,
          depth,
          doc_delim,
          indent_size,
          prefix,
          n,
          delim_sym
        )
    end
  end

  defp encode_tabular_kv(
         encoded_key,
         list,
         doc_delim,
         indent_size,
         prefix,
         depth,
         n,
         delim_sym
       ) do
    # Extract field order from the first row
    [{_, _} | _] = first = hd(list)
    fields = Enum.map(first, fn {k, _} -> k end)
    encoded_fields = Enum.map(fields, &encode_key/1)
    fields_str = Enum.join(encoded_fields, <<doc_delim>>)
    row_prefix = String.duplicate(" ", (depth + 1) * indent_size)

    rows =
      Enum.map(list, fn pairs ->
        values =
          Enum.map(fields, fn f ->
            v = find_value(pairs, f)
            Primitives.encode_primitive(v, doc_delim)
          end)

        "#{row_prefix}#{Enum.join(values, <<doc_delim>>)}"
      end)

    "#{prefix}#{encoded_key}[#{n}#{delim_sym}]{#{fields_str}}:\n#{Enum.join(rows, "\n")}"
  end

  defp encode_expanded_kv(
         encoded_key,
         list,
         opts,
         path,
         depth,
         doc_delim,
         indent_size,
         prefix,
         n,
         delim_sym
       ) do
    item_prefix = String.duplicate(" ", (depth + 1) * indent_size)

    items =
      list
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        item_path = path ++ [idx]
        encode_list_item(item, opts, item_path, depth + 1, doc_delim, indent_size, item_prefix)
      end)

    "#{prefix}#{encoded_key}[#{n}#{delim_sym}]:\n#{Enum.join(items, "\n")}"
  end

  # ---------------------------------------------------------------------------
  # Array encoding (standalone, no key context)
  # ---------------------------------------------------------------------------

  defp encode_array_standalone(list, opts, path, depth, doc_delim) do
    indent_size = Keyword.get(opts, :indent, 2)
    n = length(list)
    delim_sym = delimiter_symbol(doc_delim)
    prefix = String.duplicate(" ", depth * indent_size)

    cond do
      all_primitives?(list) ->
        values = Enum.map(list, &Primitives.encode_primitive(&1, doc_delim))
        "#{prefix}[#{n}#{delim_sym}]: #{Enum.join(values, <<doc_delim>>)}"

      tabular?(list) ->
        [{_, _} | _] = first = hd(list)
        fields = Enum.map(first, fn {k, _} -> k end)
        encoded_fields = Enum.map(fields, &encode_key/1)
        fields_str = Enum.join(encoded_fields, <<doc_delim>>)
        row_prefix = String.duplicate(" ", (depth + 1) * indent_size)

        rows =
          Enum.map(list, fn pairs ->
            values =
              Enum.map(fields, fn f ->
                v = find_value(pairs, f)
                Primitives.encode_primitive(v, doc_delim)
              end)

            "#{row_prefix}#{Enum.join(values, <<doc_delim>>)}"
          end)

        "#{prefix}[#{n}#{delim_sym}]{#{fields_str}}:\n#{Enum.join(rows, "\n")}"

      true ->
        item_prefix = String.duplicate(" ", (depth + 1) * indent_size)

        items =
          list
          |> Enum.with_index()
          |> Enum.map(fn {item, idx} ->
            encode_list_item(
              item,
              opts,
              path ++ [idx],
              depth + 1,
              doc_delim,
              indent_size,
              item_prefix
            )
          end)

        "#{prefix}[#{n}#{delim_sym}]:\n#{Enum.join(items, "\n")}"
    end
  end

  # ---------------------------------------------------------------------------
  # List item encoding (prefixed with "- ")
  # ---------------------------------------------------------------------------

  defp encode_list_item(item, opts, path, depth, doc_delim, indent_size, item_prefix) do
    case item do
      nil -> "#{item_prefix}- null"
      true -> "#{item_prefix}- true"
      false -> "#{item_prefix}- false"
      n when is_integer(n) -> "#{item_prefix}- #{n}"
      f when is_float(f) -> "#{item_prefix}- #{Primitives.encode_primitive(f, doc_delim)}"
      s when is_binary(s) -> "#{item_prefix}- #{Primitives.encode_primitive(s, doc_delim)}"
      [] ->
        delim_sym = delimiter_symbol(doc_delim)
        "#{item_prefix}- [0#{delim_sym}]:"

      [{_, _} | _] = pairs ->
        # Object as list item: emit the hyphen on its own line, then the object block
        child_block = encode_object(pairs, opts, path, depth + 1)
        "#{item_prefix}-\n#{child_block}"

      list when is_list(list) ->
        sub_n = length(list)
        delim_sym = delimiter_symbol(doc_delim)

        if all_primitives?(list) do
          values = Enum.map(list, &Primitives.encode_primitive(&1, doc_delim))
          "#{item_prefix}- [#{sub_n}#{delim_sym}]: #{Enum.join(values, <<doc_delim>>)}"
        else
          sub_prefix = String.duplicate(" ", (depth + 1) * indent_size)

          sub_items =
            list
            |> Enum.with_index()
            |> Enum.map(fn {sub, idx} ->
              encode_list_item(
                sub,
                opts,
                path ++ [idx],
                depth + 1,
                doc_delim,
                indent_size,
                sub_prefix
              )
            end)

          "#{item_prefix}- [#{sub_n}#{delim_sym}]:\n#{Enum.join(sub_items, "\n")}"
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp encode_key(key) do
    if StringUtils.key_needs_quoting?(key) do
      "\"#{StringUtils.escape(key)}\""
    else
      key
    end
  end

  # Returns true when every element is a TOON primitive (nil, boolean, number, string)
  defp all_primitives?(list) do
    Enum.all?(list, fn
      v when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v) -> true
      _ -> false
    end)
  end

  # Tabular: all elements are objects (ordered pairs) with the same keys, all values primitive.
  # Key order is taken from the first element; rows must have the same key set (order-insensitive).
  defp tabular?([]), do: false

  defp tabular?(list) do
    case hd(list) do
      [{_, _} | _] = first ->
        first_keys = Enum.map(first, fn {k, _} -> k end) |> Enum.sort()

        Enum.all?(list, fn
          [{_, _} | _] = pairs ->
            row_keys = Enum.map(pairs, fn {k, _} -> k end) |> Enum.sort()

            row_keys == first_keys and
              Enum.all?(pairs, fn {_, v} ->
                is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v)
              end)

          _ ->
            false
        end)

      _ ->
        false
    end
  end

  # Lookup a value in an ordered pairs list by key (used for tabular row rendering)
  defp find_value(pairs, key) do
    case List.keyfind(pairs, key, 0) do
      {_, v} -> v
      nil -> nil
    end
  end

  defp resolve_delimiter(:comma), do: ?,
  defp resolve_delimiter(:tab), do: ?\t
  defp resolve_delimiter(:pipe), do: ?|
  defp resolve_delimiter(c) when is_integer(c), do: c

  # Returns the suffix appended to array length in headers:
  # comma (default) is omitted; tab and pipe are written explicitly.
  defp delimiter_symbol(?,), do: ""
  defp delimiter_symbol(?\t), do: "\t"
  defp delimiter_symbol(?|), do: "|"
end
