defmodule Toon.ReplacerTest do
  use ExUnit.Case, async: true

  describe "basic filtering" do
    test "removes properties by returning :skip" do
      input = %{"name" => "Alice", "password" => "secret", "email" => "alice@example.com"}

      replacer = fn key, _value, _path ->
        if key == "password", do: :skip, else: :keep
      end

      assert {:ok, result} = Toon.encode(input, replacer: replacer)
      assert {:ok, decoded} = Toon.decode(result)
      assert decoded == %{"name" => "Alice", "email" => "alice@example.com"}
      refute Map.has_key?(decoded, "password")
    end

    test "removes array elements by returning :skip" do
      input = [1, 2, 3, 4, 5]

      replacer = fn _key, value, _path ->
        if is_integer(value) and rem(value, 2) == 0, do: :skip, else: :keep
      end

      assert {:ok, result} = Toon.encode(input, replacer: replacer)
      assert {:ok, decoded} = Toon.decode(result)
      assert decoded == [1, 3, 5]
    end

    test "handles deeply nested filtering" do
      input = %{
        "users" => [
          %{"name" => "Alice", "password" => "secret1", "role" => "admin"},
          %{"name" => "Bob", "password" => "secret2", "role" => "user"}
        ]
      }

      replacer = fn key, _value, _path ->
        if key == "password", do: :skip, else: :keep
      end

      assert {:ok, result} = Toon.encode(input, replacer: replacer)
      assert {:ok, decoded} = Toon.decode(result)

      assert decoded == %{
               "users" => [
                 %{"name" => "Alice", "role" => "admin"},
                 %{"name" => "Bob", "role" => "user"}
               ]
             }
    end
  end

  describe "value transformation" do
    test "transforms primitive values" do
      input = %{"name" => "alice", "age" => 30}

      replacer = fn _key, value, _path ->
        if is_binary(value), do: {:replace, String.upcase(value)}, else: :keep
      end

      assert {:ok, result} = Toon.encode(input, replacer: replacer)
      assert {:ok, decoded} = Toon.decode(result)
      assert decoded == %{"name" => "ALICE", "age" => 30}
    end

    test "transforms objects using path" do
      input = %{"user" => %{"name" => "Alice"}}

      replacer = fn key, value, path ->
        if length(path) == 1 and is_map(value) and not is_list(value) do
          {:replace, Map.put(value, "_id", "#{key}_123")}
        else
          :keep
        end
      end

      assert {:ok, result} = Toon.encode(input, replacer: replacer)
      assert {:ok, decoded} = Toon.decode(result)
      assert Map.has_key?(decoded["user"], "_id")
      assert decoded["user"]["_id"] == "user_123"
    end

    test "transforms root value" do
      input = %{"name" => "Alice"}

      replacer = fn key, value, _path ->
        if key == "" do
          {:replace, Map.put(value, "extra", "added")}
        else
          :keep
        end
      end

      assert {:ok, result} = Toon.encode(input, replacer: replacer)
      assert {:ok, decoded} = Toon.decode(result)
      assert decoded["extra"] == "added"
    end
  end

  describe "path tracking" do
    test "path reflects object nesting depth" do
      paths_seen = :ets.new(:paths, [:set, :public])

      input = %{"a" => %{"b" => %{"c" => "deep"}}}

      replacer = fn key, value, path ->
        :ets.insert(paths_seen, {key, path})
        {:replace, value}
      end

      Toon.encode(input, replacer: replacer)
      assert {_, ["a", "b"]} = :ets.lookup(paths_seen, "c") |> hd()
      :ets.delete(paths_seen)
    end

    test "path uses integer index for array elements" do
      paths_seen = :ets.new(:arr_paths, [:set, :public])

      input = %{"items" => ["x", "y", "z"]}

      replacer = fn key, value, path ->
        :ets.insert(paths_seen, {key, path})
        {:replace, value}
      end

      Toon.encode(input, replacer: replacer)
      # Array element at index 0 should have path ["items", 0]
      assert {_, ["items", 0]} = :ets.lookup(paths_seen, "0") |> hd()
      :ets.delete(paths_seen)
    end
  end

  describe "edge cases" do
    test "replacer returning nil wraps in null" do
      input = %{"name" => "Alice", "value" => 42}

      replacer = fn key, _value, _path ->
        if key == "value", do: {:replace, nil}, else: :keep
      end

      assert {:ok, result} = Toon.encode(input, replacer: replacer)
      assert {:ok, decoded} = Toon.decode(result)
      assert decoded["value"] == nil
    end

    test "skipping root is a no-op (root cannot be omitted)" do
      # Per spec: returning :skip for the root key is treated as :keep
      replacer = fn _key, _value, _path -> :skip end
      assert {:ok, result} = Toon.encode(%{"a" => 1}, replacer: replacer)
      # Root object is still emitted, but all keys are skipped — empty object
      assert {:ok, decoded} = Toon.decode(result)
      assert decoded == %{}
    end

    test "no replacer option equals identity replacer" do
      value = %{"name" => "Alice", "age" => 30}
      {:ok, without_replacer} = Toon.encode(value)
      {:ok, with_identity} = Toon.encode(value, replacer: fn _k, _v, _p -> :keep end)
      assert without_replacer == with_identity
    end
  end
end
