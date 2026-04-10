defmodule Toon.EncodeError do
  @moduledoc """
  Raised by `Toon.encode!/2` when the input cannot be normalized to the TOON data model.
  """

  defexception [:reason, :message, :path]

  @type t :: %__MODULE__{
          reason: atom(),
          message: String.t(),
          path: [String.t() | non_neg_integer()]
        }
end
