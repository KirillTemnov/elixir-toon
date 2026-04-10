defmodule Toon.DecodeStreamTest do
  use ExUnit.Case, async: true

  describe "decode_stream_sync/2" do
    test "decode simple object emits correct events" do
      lines = String.split("name: Alice\nage: 30", "\n")
      events = Toon.decode_stream_sync(lines) |> Enum.to_list()

      assert events == [
        %{type: :start_object},
        %{type: :key, key: "name"},
        %{type: :primitive, value: "Alice"},
        %{type: :key, key: "age"},
        %{type: :primitive, value: 30},
        %{type: :end_object}
      ]
    end

    test "decode nested object emits correct events" do
      lines = String.split("user:\n  name: Alice\n  age: 30", "\n")
      events = Toon.decode_stream_sync(lines) |> Enum.to_list()

      assert events == [
        %{type: :start_object},
        %{type: :key, key: "user"},
        %{type: :start_object},
        %{type: :key, key: "name"},
        %{type: :primitive, value: "Alice"},
        %{type: :key, key: "age"},
        %{type: :primitive, value: 30},
        %{type: :end_object},
        %{type: :end_object}
      ]
    end

    test "decode inline primitive array emits correct events" do
      lines = ["scores[3]: 95, 87, 92"]
      events = Toon.decode_stream_sync(lines) |> Enum.to_list()

      assert events == [
        %{type: :start_object},
        %{type: :key, key: "scores"},
        %{type: :start_array, length: 3},
        %{type: :primitive, value: 95},
        %{type: :primitive, value: 87},
        %{type: :primitive, value: 92},
        %{type: :end_array},
        %{type: :end_object}
      ]
    end

    test "decode inline array with empty string key" do
      lines = [~s(""[2]: 1,2)]
      events = Toon.decode_stream_sync(lines) |> Enum.to_list()

      assert events == [
        %{type: :start_object},
        %{type: :key, key: ""},
        %{type: :start_array, length: 2},
        %{type: :primitive, value: 1},
        %{type: :primitive, value: 2},
        %{type: :end_array},
        %{type: :end_object}
      ]
    end

    test "decode list array emits correct events" do
      lines = String.split("items[2]:\n  - Apple\n  - Banana", "\n")
      events = Toon.decode_stream_sync(lines) |> Enum.to_list()

      assert events == [
        %{type: :start_object},
        %{type: :key, key: "items"},
        %{type: :start_array, length: 2},
        %{type: :primitive, value: "Apple"},
        %{type: :primitive, value: "Banana"},
        %{type: :end_array},
        %{type: :end_object}
      ]
    end

    test "decode tabular array emits correct events" do
      lines = String.split("users[2]{name,age}:\n  Alice, 30\n  Bob, 25", "\n")
      events = Toon.decode_stream_sync(lines) |> Enum.to_list()

      assert events == [
        %{type: :start_object},
        %{type: :key, key: "users"},
        %{type: :start_array, length: 2},
        %{type: :start_object},
        %{type: :key, key: "name"},
        %{type: :primitive, value: "Alice"},
        %{type: :key, key: "age"},
        %{type: :primitive, value: 30},
        %{type: :end_object},
        %{type: :start_object},
        %{type: :key, key: "name"},
        %{type: :primitive, value: "Bob"},
        %{type: :key, key: "age"},
        %{type: :primitive, value: 25},
        %{type: :end_object},
        %{type: :end_array},
        %{type: :end_object}
      ]
    end

    test "decode root primitive emits single primitive event" do
      events = Toon.decode_stream_sync(["Hello World"]) |> Enum.to_list()
      assert events == [%{type: :primitive, value: "Hello World"}]
    end

    test "decode root array emits array events" do
      lines = String.split("[2]:\n  - Apple\n  - Banana", "\n")
      events = Toon.decode_stream_sync(lines) |> Enum.to_list()

      assert events == [
        %{type: :start_array, length: 2},
        %{type: :primitive, value: "Apple"},
        %{type: :primitive, value: "Banana"},
        %{type: :end_array}
      ]
    end

    test "decode empty input emits empty object" do
      events = Toon.decode_stream_sync([]) |> Enum.to_list()
      assert events == [%{type: :start_object}, %{type: :end_object}]
    end

    test "strict mode raises on length mismatch" do
      lines = String.split("items[2]:\n  - Apple", "\n")

      assert_raise Toon.DecodeError, fn ->
        Toon.decode_stream_sync(lines, strict: true) |> Enum.to_list()
      end
    end

    test "non-strict mode allows count mismatch" do
      lines = String.split("items[2]:\n  - Apple", "\n")
      events = Toon.decode_stream_sync(lines, strict: false) |> Enum.to_list()
      assert is_list(events)
      assert hd(events) == %{type: :start_object}
    end
  end

  describe "event_builder: build_value_from_events/1" do
    test "builds object from events" do
      events = [
        %{type: :start_object},
        %{type: :key, key: "name"},
        %{type: :primitive, value: "Alice"},
        %{type: :key, key: "age"},
        %{type: :primitive, value: 30},
        %{type: :end_object}
      ]

      assert Toon.Decoder.EventBuilder.build(events) == %{"name" => "Alice", "age" => 30}
    end

    test "builds nested object from events" do
      events = [
        %{type: :start_object},
        %{type: :key, key: "user"},
        %{type: :start_object},
        %{type: :key, key: "name"},
        %{type: :primitive, value: "Alice"},
        %{type: :end_object},
        %{type: :end_object}
      ]

      assert Toon.Decoder.EventBuilder.build(events) == %{"user" => %{"name" => "Alice"}}
    end

    test "builds array from events" do
      events = [
        %{type: :start_array, length: 3},
        %{type: :primitive, value: 1},
        %{type: :primitive, value: 2},
        %{type: :primitive, value: 3},
        %{type: :end_array}
      ]

      assert Toon.Decoder.EventBuilder.build(events) == [1, 2, 3]
    end

    test "builds primitive from single event" do
      assert Toon.Decoder.EventBuilder.build([%{type: :primitive, value: "Hello"}]) == "Hello"
    end

    test "raises on incomplete event stream" do
      events = [%{type: :start_object}, %{type: :key, key: "name"}]

      assert_raise Toon.DecodeError, ~r/incomplete/i, fn ->
        Toon.Decoder.EventBuilder.build(events)
      end
    end
  end

  describe "decode_from_lines/2" do
    test "produces same result as decode/2" do
      input = "name: Alice\nage: 30\nscores[3]: 95, 87, 92"
      {:ok, from_string} = Toon.decode(input)
      {:ok, from_lines} = Toon.decode_from_lines(String.split(input, "\n"))
      assert from_lines == from_string
    end

    test "supports expand_paths option" do
      lines = String.split("user.name: Alice\nuser.age: 30", "\n")
      assert {:ok, result} = Toon.decode_from_lines(lines, expand_paths: :safe)
      assert result == %{"user" => %{"name" => "Alice", "age" => 30}}
    end

    test "handles complex nested structures with lists" do
      input =
        """
        users[2]:
          - name: Alice
            scores[3]: 95, 87, 92
          - name: Bob
            scores[3]: 88, 91, 85
        """
        |> String.trim_trailing()

      {:ok, from_string} = Toon.decode(input)
      {:ok, from_lines} = Toon.decode_from_lines(String.split(input, "\n"))

      assert from_lines == from_string

      assert from_lines == %{
               "users" => [
                 %{"name" => "Alice", "scores" => [95, 87, 92]},
                 %{"name" => "Bob", "scores" => [88, 91, 85]}
               ]
             }
    end

    test "handles tabular arrays" do
      input =
        """
        users[3]{name,age,city}:
          Alice, 30, NYC
          Bob, 25, LA
          Charlie, 35, SF
        """
        |> String.trim_trailing()

      {:ok, result} = Toon.decode_from_lines(String.split(input, "\n"))

      assert result == %{
               "users" => [
                 %{"name" => "Alice", "age" => 30, "city" => "NYC"},
                 %{"name" => "Bob", "age" => 25, "city" => "LA"},
                 %{"name" => "Charlie", "age" => 35, "city" => "SF"}
               ]
             }
    end
  end

  describe "streaming equivalence" do
    @test_cases [
      {"simple object", "name: Alice\nage: 30"},
      {"nested objects", "user:\n  profile:\n    name: Alice\n    age: 30"},
      {"mixed structures",
       "name: Alice\nscores[3]: 95, 87, 92\naddress:\n  city: NYC\n  zip: 10001"},
      {"list array with objects",
       "users[2]:\n  - name: Alice\n    age: 30\n  - name: Bob\n    age: 25"},
      {"root primitive number", "42"},
      {"root primitive string", "Hello World"},
      {"root primitive boolean", "true"},
      {"root primitive null", "null"}
    ]

    for {name, input} <- @test_cases do
      @input input

      test "decode_from_lines matches decode for: #{name}" do
        {:ok, from_string} = Toon.decode(@input)
        {:ok, from_lines} = Toon.decode_from_lines(String.split(@input, "\n"))
        assert from_lines == from_string
      end
    end
  end
end
