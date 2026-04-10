defmodule Toon.Encoder.Primitives do
  @moduledoc false

  alias Toon.StringUtils

  # Encode a normalized primitive value to its TOON string representation.
  # active_delimiter is the charcode of the current active delimiter.
  @spec encode_primitive(term(), integer()) :: String.t()
  def encode_primitive(nil, _delim), do: "null"
  def encode_primitive(true, _delim), do: "true"
  def encode_primitive(false, _delim), do: "false"
  def encode_primitive(n, _delim) when is_integer(n), do: Integer.to_string(n)

  def encode_primitive(f, _delim) when is_float(f) do
    encode_float(f)
  end

  def encode_primitive(s, delim) when is_binary(s) do
    if StringUtils.needs_quoting?(s, delim) do
      "\"" <> StringUtils.escape(s) <> "\""
    else
      s
    end
  end

  # Encode a float without scientific notation, stripping insignificant trailing zeros.
  # Uses :erlang.float_to_binary/2 with :compact and high decimal precision to avoid
  # scientific notation for values in the normal range. The result is stripped of
  # trailing zeros, so 1.50 → "1.5" and 2.0 → "2".
  defp encode_float(f) do
    str = :erlang.float_to_binary(f, [:compact, decimals: 15])
    strip_trailing_zeros(str)
  end

  # Remove trailing zeros after decimal point. If the decimal point ends up bare
  # (e.g., "3."), strip the dot too — making it indistinguishable from an integer
  # representation. Per TOON spec §3, 1.0 encodes as "1".
  defp strip_trailing_zeros(str) do
    if String.contains?(str, ".") do
      str
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    else
      str
    end
  end
end
