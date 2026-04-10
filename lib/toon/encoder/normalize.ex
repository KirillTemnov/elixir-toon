defmodule Toon.Encoder.Normalize do
  @moduledoc false

  alias Toon.{Encodable, EncodeError}

  # Recursively normalize an Elixir term to a json_value() representation
  # suitable for the TOON encoder.
  #
  # Objects are returned as ordered lists of {String.t(), term()} pairs to preserve
  # key insertion order. Plain maps use sorted key order for determinism.
  # Arrays are returned as [term()] where elements are NOT all binary-keyed tuples.
  @spec normalize(term()) :: term()
  def normalize(nil), do: nil
  def normalize(true), do: true
  def normalize(false), do: false
  def normalize(n) when is_integer(n), do: n

  def normalize(f) when is_float(f) do
    cond do
      # NaN (f != f is the standard IEEE 754 identity for NaN)
      f != f -> nil
      # Infinity check via :math.isnan/:erlang is not available; use comparison
      # against a value we know exceeds the max finite float (1.7976931348623157e+308)
      f > 1.7976931348623157e308 -> nil
      f < -1.7976931348623157e308 -> nil
      # Collapse -0.0 to integer 0 (TOON has no negative zero)
      f == 0.0 -> 0
      true -> f
    end
  end

  def normalize(s) when is_binary(s), do: s

  def normalize(a) when is_atom(a) do
    case a do
      :nan -> nil
      :infinity -> nil
      :neg_infinity -> nil
      # All other atoms convert to their string representation
      _ -> Atom.to_string(a)
    end
  end

  def normalize(list) when is_list(list) do
    cond do
      list == [] ->
        []

      # Rule 1: keyword list (all atom keys, 2-tuples) with unique keys → ordered object
      Keyword.keyword?(list) ->
        keys = Enum.map(list, fn {k, _} -> k end)
        unique_keys = Enum.uniq(keys)

        if length(keys) == length(unique_keys) do
          Enum.map(list, fn {k, v} -> {Atom.to_string(k), normalize(v)} end)
        else
          dup = keys -- unique_keys
          raise %EncodeError{
            reason: :duplicate_key,
            message: "duplicate key in keyword list: #{inspect(hd(dup))}"
          }
        end

      # Rules 2 & 3: list of 2-tuples with binary or atom first element → ordered object
      tuple_object?(list) ->
        keys = Enum.map(list, fn {k, _} -> normalize_key(k) end)
        unique_keys = Enum.uniq(keys)

        if length(keys) == length(unique_keys) do
          Enum.map(list, fn {k, v} -> {normalize_key(k), normalize(v)} end)
        else
          dup = keys -- unique_keys

          raise %EncodeError{
            reason: :duplicate_key,
            message: "duplicate key: #{inspect(hd(dup))}"
          }
        end

      # Otherwise: plain list (tuples inside are recursively converted to lists)
      true ->
        Enum.map(list, &normalize/1)
    end
  end

  # Tuples become lists (their elements normalized)
  def normalize(tuple) when is_tuple(tuple), do: normalize(Tuple.to_list(tuple))

  def normalize(map) when is_map(map) do
    if is_struct(map) do
      # If Toon.Encodable is implemented for this struct, use it; otherwise fall back
      # to Map.from_struct/1. We check impl_for/1 at runtime before dispatching to
      # avoid Protocol.UndefinedError when no implementation exists.
      case Encodable.impl_for(map) do
        nil ->
          map |> Map.from_struct() |> normalize()

        impl ->
          # Call via apply/3 to satisfy the type checker — impl is a module atom
          # that implements the Toon.Encodable protocol for this struct's type.
          apply(impl, :to_toon, [map]) |> normalize()
      end
    else
      # Plain maps: deterministic output via sorted keys
      map
      |> Enum.sort_by(fn {k, _} -> normalize_key(k) end)
      |> Enum.map(fn {k, v} -> {normalize_key(k), normalize(v)} end)
    end
  end

  def normalize(term) do
    raise %EncodeError{
      reason: :unencodable_term,
      message: "cannot encode term: #{inspect(term)}"
    }
  end

  # Helpers

  defp normalize_key(k) when is_atom(k), do: Atom.to_string(k)
  defp normalize_key(k) when is_binary(k), do: k

  # Returns true if every element is a 2-tuple with a binary or atom first element.
  # Empty lists return false (handled separately above).
  defp tuple_object?(list) do
    Enum.all?(list, fn
      {k, _} when is_binary(k) or is_atom(k) -> true
      _ -> false
    end)
  end
end
