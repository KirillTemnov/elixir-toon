defmodule Toon.Decoder.Core do
  @moduledoc false

  # Pipeline orchestrator for the TOON decoder.
  #
  # decode_lines/2 runs the full decode pipeline:
  #   1. Scanner.scan_lines/1  — [String.t()] → [%Scanner{}] + indent_size
  #   2. StrictMode.validate_lines/2 (if strict: true) — validates indentation
  #   3. Parser.parse/3 — [%Scanner{}] → [event()]
  #   4. EventBuilder.build/1 — [event()] → json_value()
  #   5. Expand.expand/1 (if expand_paths: :safe) — expands dotted keys

  alias Toon.DecodeError
  alias Toon.Decoder.{Scanner, Parser, EventBuilder, StrictMode, Expand}

  @spec decode_lines(Enumerable.t(), keyword()) ::
          {:ok, term()} | {:error, DecodeError.t()}
  def decode_lines(lines, opts) do
    strict = Keyword.get(opts, :strict, true)
    expand_paths = Keyword.get(opts, :expand_paths, :off)

    try do
      lines_list = Enum.to_list(lines)

      # Step 1: scan into ParsedLine structs
      {:ok, parsed_lines, indent_size} = Scanner.scan_lines(lines_list)

      # Step 2: strict-mode indentation validation
      if strict do
        case StrictMode.validate_lines(parsed_lines, indent_size) do
          :ok -> :ok
          {:error, e} -> throw({:decode_error, e})
        end
      end

      # Step 3: parse events from the line stream
      # Parser.parse/3 returns {:ok, events}; errors surface as thrown DecodeError
      # or matched by the rescue clause below.
      {:ok, events} = Parser.parse(parsed_lines, indent_size, strict)

      # Step 4: build the value tree from events
      value = EventBuilder.build(events)

      # Step 5: optional path expansion
      result =
        if expand_paths == :safe do
          Expand.expand(value)
        else
          value
        end

      {:ok, result}
    rescue
      e in DecodeError -> {:error, e}
    catch
      {:decode_error, e} -> {:error, e}
    end
  end
end
