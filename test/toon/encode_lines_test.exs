defmodule Toon.EncodeLinesTest do
  use ExUnit.Case, async: true

  test "yields lines without newline characters" do
    value = %{"name" => "Alice", "age" => 30, "city" => "Paris"}
    lines = Toon.encode_lines(value) |> Enum.to_list()

    for line <- lines do
      refute String.contains?(line, "\n"),
             "Expected line to not contain newline, got: #{inspect(line)}"
    end
  end

  test "yields zero lines for empty map" do
    lines = Toon.encode_lines(%{}) |> Enum.to_list()
    assert lines == []
  end

  test "is enumerable with Enum.each" do
    value = %{"x" => 10, "y" => 20}
    collected = Toon.encode_lines(value) |> Enum.to_list()

    assert length(collected) == 2
    # Maps encode in sorted key order
    assert collected == ["x: 10", "y: 20"]
  end

  test "lines have no trailing whitespace" do
    value = %{
      "user" => %{
        "name" => "Alice",
        "tags" => ["a", "b"],
        "nested" => %{"deep" => "value"}
      }
    }

    lines = Toon.encode_lines(value) |> Enum.to_list()

    for line <- lines do
      refute String.match?(line, ~r/\s$/),
             "Expected line to have no trailing whitespace, got: #{inspect(line)}"
    end
  end

  test "yields correct number of lines for flat object" do
    lines = Toon.encode_lines(%{"a" => 1, "b" => 2, "c" => 3}) |> Enum.to_list()
    assert length(lines) == 3
  end

  test "joining lines with newline equals encode result" do
    value = %{"name" => "Alice", "scores" => [1, 2, 3]}
    {:ok, encoded} = Toon.encode(value)
    from_lines = Toon.encode_lines(value) |> Enum.join("\n")
    assert from_lines == encoded
  end
end
