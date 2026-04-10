defmodule Toon.DecodeError do
  @moduledoc """
  Raised or returned when `Toon.decode/2` encounters malformed input.
  """

  defexception [:line, :column, :reason, :message]

  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          reason: atom(),
          message: String.t()
        }
end
