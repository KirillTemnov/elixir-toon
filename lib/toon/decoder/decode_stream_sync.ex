defmodule Toon.Decoder.DecodeStreamSync do
  @moduledoc false

  # Synchronous event stream decoder.
  #
  # Runs the scanner and parser pipeline and returns the resulting event list
  # as an Enumerable. Useful for tests that inspect the raw event stream before
  # EventBuilder assembles the final value.
  #
  # When strict: true, raises Toon.DecodeError if StrictMode validation fails.
  # Errors thrown by the parser via throw({:decode_error, e}) are re-raised as
  # Toon.DecodeError exceptions.

  alias Toon.DecodeError
  alias Toon.Decoder.{Scanner, Parser, StrictMode}

  @spec decode(Enumerable.t(), keyword()) :: Enumerable.t()
  def decode(lines, opts \\ []) do
    strict = Keyword.get(opts, :strict, false)

    try do
      lines_list = Enum.to_list(lines)

      {:ok, parsed_lines, indent_size} = Scanner.scan_lines(lines_list)

      if strict do
        case StrictMode.validate_lines(parsed_lines, indent_size) do
          :ok -> :ok
          {:error, e} -> raise e
        end
      end

      {:ok, events} = Parser.parse(parsed_lines, indent_size, strict)
      events
    rescue
      e in DecodeError -> raise e
    catch
      {:decode_error, %DecodeError{} = e} -> raise e
    end
  end
end
