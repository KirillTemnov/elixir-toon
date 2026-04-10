defmodule Toon.Decoder.EventBuilder do
  @moduledoc false

  # Consumes a flat list of stream events produced by Parser and assembles
  # the final json_value() tree.
  #
  # Event types consumed:
  #   %{type: :primitive, value: v}
  #   %{type: :start_object} ... %{type: :key, key: k} VALUE ... %{type: :end_object}
  #   %{type: :start_array, length: n} ... VALUE* ... %{type: :end_array}

  alias Toon.DecodeError

  # Build a json_value() from a list of stream events.
  # Raises Toon.DecodeError on incomplete or malformed event streams.
  @spec build([map()]) :: term()
  def build(events) do
    case do_build(events) do
      {value, []} ->
        value

      {_value, remaining} when remaining != [] ->
        raise %DecodeError{
          reason: :incomplete_stream,
          message: "Unexpected events after root value: #{inspect(hd(remaining))}"
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Internal recursive builder — returns {value, remaining_events}
  # ---------------------------------------------------------------------------

  defp do_build([]) do
    raise %DecodeError{
      reason: :incomplete_stream,
      message: "Incomplete event stream: no events to build from"
    }
  end

  defp do_build([%{type: :primitive, value: v} | rest]) do
    {v, rest}
  end

  defp do_build([%{type: :start_object} | rest]) do
    {pairs, remaining} = collect_object(rest, [])
    {Map.new(pairs), remaining}
  end

  defp do_build([%{type: :start_array} | rest]) do
    {items, remaining} = collect_array(rest, [])
    {items, remaining}
  end

  defp do_build([event | _]) do
    raise %DecodeError{
      reason: :incomplete_stream,
      message: "Unexpected event: #{inspect(event)}"
    }
  end

  # ---------------------------------------------------------------------------
  # Object collector — reads key/value pairs until :end_object
  # ---------------------------------------------------------------------------

  defp collect_object([%{type: :end_object} | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp collect_object([%{type: :key, key: k} | rest], acc) do
    {value, remaining} = do_build(rest)
    collect_object(remaining, [{k, value} | acc])
  end

  defp collect_object([], _acc) do
    raise %DecodeError{
      reason: :incomplete_stream,
      message: "Incomplete event stream: missing :end_object"
    }
  end

  defp collect_object([event | _], _acc) do
    raise %DecodeError{
      reason: :incomplete_stream,
      message: "Expected :key or :end_object, got: #{inspect(event)}"
    }
  end

  # ---------------------------------------------------------------------------
  # Array collector — reads values until :end_array
  # ---------------------------------------------------------------------------

  defp collect_array([%{type: :end_array} | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp collect_array([] = _events, _acc) do
    raise %DecodeError{
      reason: :incomplete_stream,
      message: "Incomplete event stream: missing :end_array"
    }
  end

  defp collect_array(events, acc) do
    {value, remaining} = do_build(events)
    collect_array(remaining, [value | acc])
  end
end
