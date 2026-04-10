defmodule Toon.Decoder.Scanner do
  @moduledoc false

  # Line tokenizer and header parser for the TOON decoder.
  #
  # Responsibilities:
  # - Scan a list of raw line strings into %Scanner{} structs (depth, indent, content)
  # - Auto-detect indent_size from the first indented non-blank line (default 2)
  # - Parse array header syntax: key[N][delim]{fields}: [inline_values]
  # - Parse key:value syntax with quoted-string awareness
  # - Split values by an active delimiter while respecting quoted strings

  alias Toon.{DecodeError, StringUtils}

  defstruct [:raw, :depth, :indent, :content, :line_number]

  @type t :: %__MODULE__{
          raw: String.t(),
          depth: non_neg_integer(),
          # leading spaces count
          indent: non_neg_integer(),
          # trimmed content (no leading spaces)
          content: String.t(),
          line_number: non_neg_integer()
        }

  # Scan a list of line strings into Scanner structs.
  # Auto-detects indent_size from first indented non-blank line.
  # Returns {:ok, [t()], indent_size} | {:error, DecodeError.t()}
  @spec scan_lines([String.t()]) :: {:ok, [t()], pos_integer()} | {:error, DecodeError.t()}
  def scan_lines(lines) do
    indent_size = detect_indent_size(lines)
    {:ok, do_scan(lines, indent_size, 1, []), indent_size}
  end

  defp detect_indent_size(lines) do
    Enum.find_value(lines, 2, fn line ->
      spaces = count_leading_spaces(line)
      if spaces > 0 and String.trim(line) != "", do: spaces, else: nil
    end)
  end

  defp do_scan([], _indent_size, _ln, acc), do: Enum.reverse(acc)

  defp do_scan([line | rest], indent_size, ln, acc) do
    spaces = count_leading_spaces(line)
    content = String.slice(line, spaces, String.length(line))
    depth = if indent_size > 0, do: div(spaces, indent_size), else: 0

    parsed = %__MODULE__{
      raw: line,
      depth: depth,
      indent: spaces,
      content: content,
      line_number: ln
    }

    do_scan(rest, indent_size, ln + 1, [parsed | acc])
  end

  defp count_leading_spaces(line) do
    case Regex.run(~r/^( *)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end

  # Parse an array header from a line's content.
  # Returns:
  #   {:array_header, key_or_nil, length, delimiter, fields_or_nil, inline_or_nil}
  #   | :not_header
  #
  # Examples:
  #   "users[3]{id,name}:" → {:array_header, "users", 3, 44, ["id", "name"], nil}
  #   "[2]:" → {:array_header, nil, 2, 44, nil, nil}
  #   "items[2\t]: a,b" → {:array_header, "items", 2, 9, nil, "a,b"}
  @spec parse_header(String.t()) ::
          {:array_header, String.t() | nil, non_neg_integer(), integer(),
           [String.t()] | nil, String.t() | nil}
          | :not_header
  def parse_header(content) do
    # Regex: optional key (quoted or unquoted), [N][optional delim char], optional {fields}, :, rest
    # Using non-extended form to avoid issues with whitespace in the pattern
    header_regex =
      ~r/^("(?:[^"\\]|\\.)*"|[A-Za-z_][A-Za-z0-9_.]*|)\[(\d+)([\t|]?)\](?:\{([^}]*)\})?:\s*(.*)$/s

    case Regex.run(header_regex, content) do
      nil ->
        :not_header

      [_, key_raw, length_str, delim_char, fields_raw, rest_str] ->
        # Validate it is actually a header — key must be valid if present
        key = parse_key(key_raw)

        if key == :error do
          :not_header
        else
          length = String.to_integer(length_str)
          delimiter = parse_delimiter_char(delim_char)
          fields = parse_fields(fields_raw, delimiter)
          inline = if String.trim(rest_str) == "", do: nil, else: String.trim(rest_str)
          {:array_header, key, length, delimiter, fields, inline}
        end
    end
  end

  # Parse a key:value line. Returns {:kv, key, value_str} | :not_kv
  @spec parse_kv(String.t()) :: {:kv, String.t(), String.t()} | :not_kv
  def parse_kv(content) do
    case find_unquoted_colon(content) do
      nil ->
        :not_kv

      idx ->
        key_raw = String.slice(content, 0, idx)
        value_str =
          content
          |> String.slice(idx + 1, String.length(content))
          |> String.trim_leading()

        key = parse_key(key_raw)

        if key == :error or key == nil do
          :not_kv
        else
          {:kv, key, value_str}
        end
    end
  end

  # Find index of first colon not inside double-quoted string
  defp find_unquoted_colon(str), do: do_find_colon(str, 0, false)

  defp do_find_colon("", _idx, _in_quotes), do: nil

  defp do_find_colon(<<"\\", _::utf8, rest::binary>>, idx, true),
    do: do_find_colon(rest, idx + 2, true)

  defp do_find_colon(<<"\"", rest::binary>>, idx, in_quotes),
    do: do_find_colon(rest, idx + 1, not in_quotes)

  defp do_find_colon(<<":", _::binary>>, idx, false), do: idx
  defp do_find_colon(<<":", _::binary>>, _idx, true), do: nil

  defp do_find_colon(<<_::utf8, rest::binary>>, idx, in_quotes),
    do: do_find_colon(rest, idx + 1, in_quotes)

  # Parse a key — quoted or unquoted, returns nil for empty, :error on bad escape
  defp parse_key(""), do: nil

  defp parse_key("\"" <> _ = quoted) do
    len = String.length(quoted)

    if len >= 2 and String.last(quoted) == "\"" do
      inner = String.slice(quoted, 1, len - 2)

      case StringUtils.unescape(inner) do
        {:ok, s} -> s
        {:error, _} -> :error
      end
    else
      :error
    end
  end

  defp parse_key(unquoted) do
    trimmed = String.trim(unquoted)
    # Unquoted keys must match [A-Za-z_][A-Za-z0-9_.]*
    if trimmed == "" do
      nil
    else
      trimmed
    end
  end

  defp parse_delimiter_char(""), do: ?,
  defp parse_delimiter_char("\t"), do: ?\t
  defp parse_delimiter_char("|"), do: ?|

  defp parse_fields("", _delim), do: nil
  defp parse_fields(nil, _delim), do: nil

  defp parse_fields(fields_raw, delim) do
    fields_raw
    |> split_by_delimiter(delim)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_key/1)
  end

  # Split a string by the active delimiter character, respecting quoted strings.
  @spec split_by_delimiter(String.t(), integer()) :: [String.t()]
  def split_by_delimiter(str, delim) do
    do_split(str, delim, [], [])
  end

  defp do_split("", _delim, current, acc) do
    segment = current |> Enum.reverse() |> IO.iodata_to_binary()
    Enum.reverse([segment | acc])
  end

  defp do_split(<<"\\", c::utf8, rest::binary>>, delim, current, acc) do
    do_split(rest, delim, [<<c::utf8>>, "\\" | current], acc)
  end

  defp do_split(<<"\"", rest::binary>>, delim, current, acc) do
    {quoted, after_quote} = consume_quoted(rest, ["\""])
    do_split(after_quote, delim, [quoted | current], acc)
  end

  defp do_split(<<c::utf8, rest::binary>>, delim, current, acc) when c == delim do
    segment = current |> Enum.reverse() |> IO.iodata_to_binary()
    do_split(rest, delim, [], [segment | acc])
  end

  defp do_split(<<c::utf8, rest::binary>>, delim, current, acc) do
    do_split(rest, delim, [<<c::utf8>> | current], acc)
  end

  # Consume everything up to and including the closing quote, returning the quoted segment
  defp consume_quoted("", acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}
  end

  defp consume_quoted(<<"\\", c::utf8, rest::binary>>, acc) do
    consume_quoted(rest, [<<c::utf8>>, "\\" | acc])
  end

  defp consume_quoted(<<"\"", rest::binary>>, acc) do
    segment = ["\"" | acc] |> Enum.reverse() |> IO.iodata_to_binary()
    {segment, rest}
  end

  defp consume_quoted(<<c::utf8, rest::binary>>, acc) do
    consume_quoted(rest, [<<c::utf8>> | acc])
  end
end
