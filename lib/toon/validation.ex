defmodule Toon.Validation do
  @moduledoc false

  alias Toon.DecodeError

  @spec validate_indent(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, DecodeError.t()}
  def validate_indent(spaces, indent_size, line_number) do
    if Integer.mod(spaces, indent_size) == 0 do
      :ok
    else
      {:error,
       %DecodeError{
         line: line_number,
         reason: :indentation_error,
         message:
           "indentation #{spaces} is not a multiple of indent_size #{indent_size} at line #{line_number}"
       }}
    end
  end
end
