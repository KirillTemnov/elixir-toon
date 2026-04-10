defmodule Toon.Decoder.Parser do
  @moduledoc false

  # Structural parser for TOON documents.
  #
  # Consumes a list of %Scanner{} structs and produces a flat list of stream events:
  #   %{type: :start_object}
  #   %{type: :end_object}
  #   %{type: :start_array, length: n}
  #   %{type: :end_array}
  #   %{type: :key, key: str}
  #   %{type: :primitive, value: val}
  #
  # Design:
  # - Recursive descent over the line list, tracking expected depth.
  # - Root form detection per §5: first depth-0 line determines array vs object vs primitive.
  # - Array forms: inline primitive, tabular rows, expanded list items.
  # - Object forms: key:value pairs at a given depth.

  alias Toon.Decoder.Scanner
  alias Toon.{LiteralUtils, StringUtils}

  @type event :: map()

  # Parse a list of Scanner structs into stream events.
  # Returns {:ok, [event()]} | {:error, term()}
  @spec parse([Scanner.t()], pos_integer(), boolean()) ::
          {:ok, [event()]} | {:error, term()}
  def parse(parsed_lines, indent_size, strict) do
    non_blank = Enum.reject(parsed_lines, fn l -> String.trim(l.raw) == "" end)

    case detect_root_form(non_blank) do
      :empty ->
        {:ok, [%{type: :start_object}, %{type: :end_object}]}

      {:root_primitive, line} ->
        {:ok, [%{type: :primitive, value: LiteralUtils.parse_primitive(line.content)}]}

      {:root_array, _line} ->
        parse_root_array(non_blank, indent_size, strict)

      :root_object ->
        parse_root_object(non_blank, indent_size, strict)
    end
  end

  # ---------------------------------------------------------------------------
  # Root form detection (§5)
  # ---------------------------------------------------------------------------

  defp detect_root_form([]), do: :empty

  defp detect_root_form(lines) do
    first = hd(lines)
    depth0_lines = Enum.filter(lines, &(&1.depth == 0))

    cond do
      match?({:array_header, _, _, _, _, _}, Scanner.parse_header(first.content)) ->
        {:root_array, first}

      length(depth0_lines) == 1 and not is_kv_line?(first) and
          not String.starts_with?(first.content, "- ") ->
        {:root_primitive, first}

      true ->
        :root_object
    end
  end

  defp is_kv_line?(line) do
    Scanner.parse_kv(line.content) != :not_kv
  end

  # ---------------------------------------------------------------------------
  # Root array
  # ---------------------------------------------------------------------------

  defp parse_root_array([header_line | rest], indent_size, strict) do
    {:array_header, _nil_key, length, delimiter, fields, inline} =
      Scanner.parse_header(header_line.content)

    {body_events, _remaining} =
      parse_array_body(rest, 1, length, delimiter, fields, inline, indent_size, strict)

    {:ok,
     [%{type: :start_array, length: length}] ++ body_events ++ [%{type: :end_array}]}
  end

  # ---------------------------------------------------------------------------
  # Root object
  # ---------------------------------------------------------------------------

  defp parse_root_object(lines, indent_size, strict) do
    {events, _remaining} = parse_object_body(lines, 0, indent_size, strict)
    {:ok, [%{type: :start_object}] ++ events ++ [%{type: :end_object}]}
  end

  # ---------------------------------------------------------------------------
  # Object body: parse key-value pairs at the given depth
  # ---------------------------------------------------------------------------

  defp parse_object_body([], _depth, _indent_size, _strict), do: {[], []}

  defp parse_object_body([line | rest] = lines, depth, indent_size, strict) do
    if line.depth < depth do
      # Depth decreased — end of this object scope
      {[], lines}
    else
      case Scanner.parse_header(line.content) do
        {:array_header, key, length, delimiter, fields, inline} when key != nil ->
          # Array-valued field
          key_event = %{type: :key, key: key}
          start_event = %{type: :start_array, length: length}

          {body_events, remaining} =
            parse_array_body(rest, depth + 1, length, delimiter, fields, inline, indent_size, strict)

          end_event = %{type: :end_array}

          {more_events, final_remaining} =
            parse_object_body(remaining, depth, indent_size, strict)

          events =
            [key_event, start_event] ++
              body_events ++
              [end_event] ++
              more_events

          {events, final_remaining}

        _ ->
          case Scanner.parse_kv(line.content) do
            {:kv, key, value_str} ->
              key_event = %{type: :key, key: key}

              {value_events, remaining} =
                parse_value(value_str, rest, depth, indent_size, strict)

              {more_events, final_remaining} =
                parse_object_body(remaining, depth, indent_size, strict)

              {[key_event] ++ value_events ++ more_events, final_remaining}

            :not_kv ->
              # Skip unrecognized line and continue
              parse_object_body(rest, depth, indent_size, strict)
          end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Value parsing (after "key:")
  # ---------------------------------------------------------------------------

  # Empty after colon — nested object or nested array
  defp parse_value("", rest, depth, indent_size, strict) do
    case rest do
      [] ->
        {[%{type: :start_object}, %{type: :end_object}], []}

      [next | _] ->
        if next.depth > depth do
          # Peek to decide: if next line is an array header without key, it's a nested array.
          # Otherwise it's a nested object.
          case Scanner.parse_header(next.content) do
            {:array_header, nil, length, delimiter, fields, inline} ->
              # Anonymous array header at child depth — nested array value
              [_header | after_header] = rest

              {body_events, remaining} =
                parse_array_body(
                  after_header,
                  depth + 2,
                  length,
                  delimiter,
                  fields,
                  inline,
                  indent_size,
                  strict
                )

              {[%{type: :start_array, length: length}] ++ body_events ++ [%{type: :end_array}],
               remaining}

            _ ->
              # Nested object
              {child_events, remaining} =
                parse_object_body(rest, depth + 1, indent_size, strict)

              {[%{type: :start_object}] ++ child_events ++ [%{type: :end_object}], remaining}
          end
        else
          {[%{type: :start_object}, %{type: :end_object}], rest}
        end
    end
  end

  # Inline primitive value after colon
  defp parse_value(value_str, rest, _depth, _indent_size, _strict) do
    value = parse_primitive_token(value_str)
    {[%{type: :primitive, value: value}], rest}
  end

  # ---------------------------------------------------------------------------
  # Array body dispatch
  # ---------------------------------------------------------------------------

  defp parse_array_body(rest, _depth, _length, _delimiter, nil, inline, _indent_size, _strict)
       when inline != nil do
    # Inline primitive array — all values on the header line itself
    values = parse_inline_values(inline, ?,)
    events = Enum.map(values, &%{type: :primitive, value: &1})
    {events, rest}
  end

  defp parse_array_body(rest, depth, length, delimiter, fields, inline, indent_size, strict) do
    cond do
      inline != nil ->
        values = parse_inline_values(inline, delimiter)
        events = Enum.map(values, &%{type: :primitive, value: &1})
        {events, rest}

      fields != nil ->
        parse_tabular_rows(rest, depth, length, delimiter, fields, indent_size, strict)

      true ->
        parse_list_items(rest, depth, delimiter, indent_size, strict)
    end
  end

  # ---------------------------------------------------------------------------
  # Inline values: split by delimiter, parse each as primitive
  # ---------------------------------------------------------------------------

  defp parse_inline_values(str, delimiter) do
    str
    |> Scanner.split_by_delimiter(delimiter)
    |> Enum.map(fn token ->
      token
      |> String.trim()
      |> parse_primitive_token()
    end)
  end

  # ---------------------------------------------------------------------------
  # Tabular rows
  # ---------------------------------------------------------------------------

  defp parse_tabular_rows([], _depth, _length, _delimiter, _fields, _indent_size, _strict) do
    {[], []}
  end

  defp parse_tabular_rows(
         [line | rest] = lines,
         depth,
         length,
         delimiter,
         fields,
         indent_size,
         strict
       ) do
    if line.depth != depth do
      {[], lines}
    else
      raw_values =
        line.content
        |> Scanner.split_by_delimiter(delimiter)
        |> Enum.map(&String.trim/1)

      # Pad or truncate to match field count for safety
      values =
        raw_values
        |> Enum.map(&parse_primitive_token/1)

      field_events =
        fields
        |> Enum.zip(values)
        |> Enum.flat_map(fn {field, value} ->
          [%{type: :key, key: field}, %{type: :primitive, value: value}]
        end)

      row_events =
        [%{type: :start_object}] ++ field_events ++ [%{type: :end_object}]

      {more_events, remaining} =
        parse_tabular_rows(rest, depth, length - 1, delimiter, fields, indent_size, strict)

      {row_events ++ more_events, remaining}
    end
  end

  # ---------------------------------------------------------------------------
  # Expanded list items
  # ---------------------------------------------------------------------------

  defp parse_list_items(lines, depth, delimiter, indent_size, strict) do
    collect_items(lines, depth, delimiter, indent_size, strict, [])
  end

  defp collect_items([], _depth, _delimiter, _indent_size, _strict, acc) do
    {acc |> Enum.reverse() |> List.flatten(), []}
  end

  defp collect_items([line | rest] = lines, depth, delimiter, indent_size, strict, acc) do
    if line.depth < depth do
      {acc |> Enum.reverse() |> List.flatten(), lines}
    else
      content = line.content

      if String.starts_with?(content, "- ") or content == "-" do
        item_content =
          if content == "-", do: "", else: String.slice(content, 2, String.length(content))

        {item_events, remaining} =
          parse_list_item_content(item_content, rest, depth, delimiter, indent_size, strict)

        collect_items(remaining, depth, delimiter, indent_size, strict, [item_events | acc])
      else
        # Not a list item — stop collecting
        {acc |> Enum.reverse() |> List.flatten(), lines}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # List item content dispatch
  # ---------------------------------------------------------------------------

  # Bare hyphen — check for nested object at depth+1
  defp parse_list_item_content("", rest, depth, _delimiter, indent_size, strict) do
    case rest do
      [] ->
        {[%{type: :start_object}, %{type: :end_object}], []}

      [next | _] ->
        if next.depth > depth do
          {child_events, remaining} = parse_object_body(rest, depth + 1, indent_size, strict)
          {[%{type: :start_object}] ++ child_events ++ [%{type: :end_object}], remaining}
        else
          {[%{type: :start_object}, %{type: :end_object}], rest}
        end
    end
  end

  defp parse_list_item_content(item_content, rest, depth, _delimiter, indent_size, strict) do
    # Try array header first (for "- [N]:" or "- key[N]:" patterns)
    case Scanner.parse_header(item_content) do
      {:array_header, key, length, delim, fields, inline} when key != nil ->
        # Object with an array field on the hyphen line: "- key[N]{...}:"
        key_event = %{type: :key, key: key}
        start_event = %{type: :start_array, length: length}

        {array_body, after_array} =
          parse_array_body(rest, depth + 1, length, delim, fields, inline, indent_size, strict)

        {more_obj, final_remaining} =
          parse_object_body(after_array, depth + 1, indent_size, strict)

        events =
          [%{type: :start_object}, key_event, start_event] ++
            array_body ++
            [%{type: :end_array}] ++
            more_obj ++
            [%{type: :end_object}]

        {events, final_remaining}

      {:array_header, nil, length, delim, fields, inline} ->
        # Root-style array as a list item: "- [N]:"
        start_event = %{type: :start_array, length: length}

        {array_body, remaining} =
          parse_array_body(rest, depth + 1, length, delim, fields, inline, indent_size, strict)

        {[start_event] ++ array_body ++ [%{type: :end_array}], remaining}

      :not_header ->
        # Try key:value (object starting on the hyphen line)
        case Scanner.parse_kv(item_content) do
          {:kv, key, value_str} ->
            key_event = %{type: :key, key: key}

            {value_events, after_value} =
              parse_value(value_str, rest, depth, indent_size, strict)

            {more_events, remaining} =
              parse_object_body(after_value, depth + 1, indent_size, strict)

            events =
              [%{type: :start_object}, key_event] ++
                value_events ++
                more_events ++
                [%{type: :end_object}]

            {events, remaining}

          :not_kv ->
            # Plain primitive list item
            value = parse_primitive_token(String.trim(item_content))
            {[%{type: :primitive, value: value}], rest}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Primitive token parsing
  # ---------------------------------------------------------------------------

  # Quoted string — unescape inner content
  defp parse_primitive_token("\"" <> _ = quoted) do
    len = String.length(quoted)

    if len >= 2 and String.last(quoted) == "\"" do
      inner = String.slice(quoted, 1, len - 2)

      case StringUtils.unescape(inner) do
        {:ok, s} -> s
        # Return raw on bad escape — strict mode catches this separately
        {:error, _} -> quoted
      end
    else
      quoted
    end
  end

  defp parse_primitive_token(token), do: LiteralUtils.parse_primitive(token)
end
