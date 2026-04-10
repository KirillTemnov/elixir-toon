defmodule Toon.Encoder.Folding do
  @moduledoc false

  # Key folding: collapse single-key wrapper chains into dotted paths.
  #
  # Example with key_folding: :safe:
  #   "a" => [{"b", [{"c", 42}]}]  →  "a.b.c" => 42
  #
  # Folding only applies when ALL of the following conditions are met:
  #   - key_folding is :safe (never :off)
  #   - the value is an object (list of {binary_key, value} pairs)
  #   - that object has exactly one key
  #   - the child key is a safe identifier: ^[A-Za-z_][A-Za-z0-9_]*$
  #   - the current (parent) key has no segments that look unsafe for dotting
  #   - the current depth has not exceeded flatten_depth
  @spec fold(String.t(), term(), :off | :safe, pos_integer() | :infinity, non_neg_integer()) ::
          {String.t(), term()}
  def fold(key, value, :off, _max_depth, _depth), do: {key, value}

  def fold(key, value, :safe, max_depth, depth) do
    do_fold(key, value, max_depth, depth)
  end

  # Recursively descend single-key chains, building up a dotted key.
  defp do_fold(key, value, max_depth, depth) when is_list(value) do
    if within_depth?(depth, max_depth) and single_key_object?(value) do
      [{child_key, child_value}] = value

      # Both segments must be safe identifiers for dot-joining
      if safe_identifier?(child_key) and safe_all_segments?(key) do
        do_fold("#{key}.#{child_key}", child_value, max_depth, depth + 1)
      else
        {key, value}
      end
    else
      {key, value}
    end
  end

  defp do_fold(key, value, _max_depth, _depth), do: {key, value}

  defp within_depth?(_depth, :infinity), do: true
  defp within_depth?(depth, max_depth), do: depth < max_depth

  # Object with exactly one entry (list of exactly one {binary_key, _} pair)
  defp single_key_object?([{k, _}]) when is_binary(k), do: true
  defp single_key_object?(_), do: false

  # Child key segment: no dots allowed (^[A-Za-z_][A-Za-z0-9_]*$)
  defp safe_identifier?(str), do: Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, str)

  # Parent key may already be dotted (from a previous fold step); each segment
  # must satisfy the identifier pattern. Accepts already-dotted keys like "a.b".
  defp safe_all_segments?(str) do
    Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_.]*$/, str)
  end
end
