defmodule Toon.StringUtils do
  @moduledoc false

  @spec needs_quoting?(String.t(), integer()) :: boolean()
  def needs_quoting?(str, active_delimiter) do
    str == "" or
      has_leading_trailing_whitespace?(str) or
      str in ["true", "false", "null"] or
      numeric_like?(str) or
      contains_special_chars?(str, active_delimiter) or
      ambiguous_sign_prefix?(str)
  end

  # §7.1: escape \, ", \n, \r, \t
  @spec escape(String.t()) :: String.t()
  def escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  # §7.1: unescape — only \\, \", \n, \r, \t are valid; anything else is an error
  @spec unescape(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def unescape(str) do
    do_unescape(str, [])
  end

  # §7.3: key encoding — unquoted only if matches ^[A-Za-z_][A-Za-z0-9_.]*$
  @spec key_needs_quoting?(String.t()) :: boolean()
  def key_needs_quoting?(key) do
    not Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.]*$/, key)
  end

  # Returns true when the string starts with "-" but is NOT a valid number literal.
  # Valid negative numbers (e.g. "-3.14", "-0") must NOT be quoted — the encoder
  # emits them as unquoted scalars per §7.2. Only non-numeric hyphen-prefixed
  # strings (e.g. "-foo", "--flag") require quoting.
  @spec ambiguous_sign_prefix?(String.t()) :: boolean()
  def ambiguous_sign_prefix?(str) do
    String.starts_with?(str, "-") and not numeric_like?(str)
  end

  defp has_leading_trailing_whitespace?(str) do
    str != String.trim(str)
  end

  defp numeric_like?(str) do
    Regex.match?(~r/^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/, str) or
      Regex.match?(~r/^0\d+$/, str)
  end

  defp contains_special_chars?(str, active_delimiter) do
    String.contains?(str, [":", "\"", "\\", "[", "]", "{", "}"]) or
      String.contains?(str, ["\n", "\r", "\t"]) or
      String.contains?(str, <<active_delimiter>>)
  end

  defp do_unescape("", acc), do: {:ok, IO.iodata_to_binary(Enum.reverse(acc))}

  defp do_unescape("\\" <> rest, acc) do
    case rest do
      "\\" <> tail -> do_unescape(tail, ["\\" | acc])
      "\"" <> tail -> do_unescape(tail, ["\"" | acc])
      "n" <> tail -> do_unescape(tail, ["\n" | acc])
      "r" <> tail -> do_unescape(tail, ["\r" | acc])
      "t" <> tail -> do_unescape(tail, ["\t" | acc])
      other ->
        bad_char = String.first(other) || "EOF"
        {:error, "invalid escape sequence: \\#{bad_char}"}
    end
  end

  defp do_unescape(<<char::utf8, rest::binary>>, acc) do
    do_unescape(rest, [<<char::utf8>> | acc])
  end
end
