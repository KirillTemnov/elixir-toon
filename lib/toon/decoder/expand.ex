defmodule Toon.Decoder.Expand do
  @moduledoc false

  # Path expansion — converts dotted keys like "a.b.c" into nested objects.
  #
  # Only expands when ALL dot-separated segments are valid unquoted identifiers
  # matching ^[A-Za-z_][A-Za-z0-9_]*$ (no dots within a segment).
  # Keys that do not match are left unchanged.
  #
  # When two keys would expand into the same path, deep_merge/2 combines them —
  # the last writer wins for scalar conflicts, and nested maps are merged.

  # Expand dotted keys in a decoded map into nested objects.
  @spec expand(term()) :: term()
  def expand(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      expanded_value = expand(value)
      segments = String.split(key, ".")

      if length(segments) > 1 and Enum.all?(segments, &valid_segment?/1) do
        nested = build_nested(segments, expanded_value)
        deep_merge(acc, nested)
      else
        Map.put(acc, key, expanded_value)
      end
    end)
  end

  def expand(list) when is_list(list), do: Enum.map(list, &expand/1)
  def expand(v), do: v

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # A valid segment is a bare identifier — no dots, starts with letter or underscore
  defp valid_segment?(seg), do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, seg)

  defp build_nested([key], value), do: %{key => value}
  defp build_nested([key | rest], value), do: %{key => build_nested(rest, value)}

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn _key, v1, v2 ->
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end
end
