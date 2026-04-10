defmodule Toon.Decoder.StrictMode do
  @moduledoc false

  # Strict-mode validation pass over scanned lines.
  #
  # Checks performed:
  # - Indentation is a multiple of indent_size (no partial-indent lines)
  # - No tab characters used as indentation (spaces only)
  # - Quoted strings have valid escape sequences

  alias Toon.{DecodeError, Validation}
  alias Toon.Decoder.Scanner

  # Validate lines for strict-mode compliance.
  # Returns :ok or {:error, DecodeError.t()} on the first violation found.
  @spec validate_lines([Scanner.t()], pos_integer()) :: :ok | {:error, DecodeError.t()}
  def validate_lines(parsed_lines, indent_size) do
    Enum.reduce_while(parsed_lines, :ok, fn line, :ok ->
      if String.trim(line.raw) == "" do
        {:cont, :ok}
      else
        with :ok <- check_indentation(line, indent_size),
             :ok <- check_escape_sequences(line) do
          {:cont, :ok}
        else
          {:error, e} -> {:halt, {:error, e}}
        end
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Indentation check
  # ---------------------------------------------------------------------------

  defp check_indentation(line, indent_size) do
    # Reject tab-based indentation
    if has_tab_indent?(line.raw) do
      {:error,
       %DecodeError{
         line: line.line_number,
         reason: :indentation_error,
         message: "Tab indentation is not allowed at line #{line.line_number}"
       }}
    else
      Validation.validate_indent(line.indent, indent_size, line.line_number)
    end
  end

  defp has_tab_indent?(raw) do
    # Tabs only matter if they appear before non-whitespace content as indent
    case Regex.run(~r/^(\s*)/, raw) do
      [_, leading] -> String.contains?(leading, "\t")
      _ -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Escape sequence check — scan for \X sequences in quoted strings
  # ---------------------------------------------------------------------------

  defp check_escape_sequences(line) do
    check_content_escapes(line.content, line.line_number)
  end

  defp check_content_escapes(content, line_number) do
    # Find all quoted strings in the content and validate each
    do_scan_escapes(content, line_number, false)
  end

  # Walk through content; when inside a quote, validate escape sequences
  defp do_scan_escapes("", _line_number, _in_quote), do: :ok

  defp do_scan_escapes(<<"\"", rest::binary>>, line_number, in_quote) do
    do_scan_escapes(rest, line_number, not in_quote)
  end

  defp do_scan_escapes(<<"\\", rest::binary>>, line_number, true) do
    case rest do
      "\\" <> tail -> do_scan_escapes(tail, line_number, true)
      "\"" <> tail -> do_scan_escapes(tail, line_number, true)
      "n" <> tail -> do_scan_escapes(tail, line_number, true)
      "r" <> tail -> do_scan_escapes(tail, line_number, true)
      "t" <> tail -> do_scan_escapes(tail, line_number, true)
      other ->
        bad_char = if byte_size(other) > 0, do: String.first(other), else: "EOF"

        {:error,
         %DecodeError{
           line: line_number,
           reason: :invalid_escape,
           message:
             "Invalid escape sequence \\#{bad_char} at line #{line_number}"
         }}
    end
  end

  defp do_scan_escapes(<<_::utf8, rest::binary>>, line_number, in_quote) do
    do_scan_escapes(rest, line_number, in_quote)
  end
end
