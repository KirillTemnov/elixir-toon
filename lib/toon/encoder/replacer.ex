defmodule Toon.Encoder.Replacer do
  @moduledoc false

  # Apply a replacer callback to a normalized value at a given key and path.
  #
  # replacer/3 signature:
  #   (key :: String.t(), value :: term(), path :: [String.t() | integer()]) ->
  #     :keep | :skip | {:replace, term()}
  #
  # - `:keep` — include the value as-is
  # - `:skip` — exclude this key/value from the output (parent handles absence)
  # - `{:replace, new_value}` — substitute the given value (caller must re-normalize)
  #
  # For the root value, key is "".
  # When replacer is nil, all values are kept unchanged.
  @spec apply(term(), function() | nil, String.t(), [String.t() | integer()]) ::
          {:keep, term()} | :skip
  def apply(value, nil, _key, _path), do: {:keep, value}

  def apply(value, replacer, key, path) do
    case replacer.(key, value, path) do
      :keep -> {:keep, value}
      :skip -> :skip
      {:replace, new_value} -> {:keep, new_value}
      # Treat any unexpected return as {:replace, result} for forward compatibility
      other -> {:keep, other}
    end
  end
end
