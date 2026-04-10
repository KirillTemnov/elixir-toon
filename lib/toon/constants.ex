defmodule Toon.Constants do
  @moduledoc false

  # Integer char-codes: comma = 44, tab = 9, pipe = 124.
  # Written as integer literals (not char literals) for Dialyzer clarity.
  @type delimiter :: 44 | 9 | 124
  @type delimiter_key :: :comma | :tab | :pipe

  @default_delimiter ?,

  @spec default_delimiter() :: integer()
  def default_delimiter, do: @default_delimiter

  @spec delimiters() :: %{delimiter_key() => delimiter()}
  def delimiters, do: %{comma: ?,, tab: ?\t, pipe: ?|}
end
