defmodule Toon.LiteralUtils do
  @moduledoc false

  @spec parse_primitive(String.t()) :: term()
  def parse_primitive("true"), do: true
  def parse_primitive("false"), do: false
  def parse_primitive("null"), do: nil

  def parse_primitive(str) do
    cond do
      leading_zero_integer?(str) -> str
      true ->
        case parse_number(str) do
          {:ok, n} -> n
          :error -> str
        end
    end
  end

  # Strings like "007" or "-007" look numeric but must stay as strings per spec §4.
  defp leading_zero_integer?(str) do
    Regex.match?(~r/^-?0\d+$/, str) and not String.contains?(str, ".")
  end

  defp parse_number(str) do
    case Float.parse(str) do
      {f, ""} ->
        if f == Float.floor(f) and not String.contains?(str, ".") and
             not String.contains?(str, "e") and not String.contains?(str, "E") do
          {:ok, trunc(f)}
        else
          {:ok, f}
        end

      _ ->
        case Integer.parse(str) do
          {i, ""} -> {:ok, i}
          _ -> :error
        end
    end
  end
end
