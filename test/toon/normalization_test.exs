defmodule Toon.NormalizationTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Structs for protocol tests must be defined at module level so they are
  # compiled before the test bodies reference them.
  # ---------------------------------------------------------------------------

  defmodule NormTestStruct do
    defstruct [:data]
  end

  defimpl Toon.Encodable, for: NormTestStruct do
    def to_toon(%{data: data}), do: %{"info" => data}
  end

  defmodule NormPrimitiveStruct do
    defstruct [:value]
  end

  defimpl Toon.Encodable, for: NormPrimitiveStruct do
    def to_toon(_), do: "custom-string"
  end

  defmodule NormListStruct do
    defstruct [:items]
  end

  defimpl Toon.Encodable, for: NormListStruct do
    def to_toon(%{items: items}), do: items
  end

  defmodule NormNestedStruct do
    defstruct [:secret]
  end

  defimpl Toon.Encodable, for: NormNestedStruct do
    def to_toon(_), do: %{"public" => "visible"}
  end

  defmodule NormRowStruct do
    defstruct [:data]
  end

  defimpl Toon.Encodable, for: NormRowStruct do
    def to_toon(%{data: d}), do: %{"transformed" => "#{d}-transformed"}
  end

  # ---------------------------------------------------------------------------
  # Integer normalization
  # ---------------------------------------------------------------------------

  describe "integer normalization" do
    test "encodes small integer normally" do
      assert {:ok, "123"} = Toon.encode(123)
    end

    test "encodes large integer as canonical decimal (no scientific notation)" do
      assert {:ok, result} = Toon.encode(9_007_199_254_740_992)
      assert result == "9007199254740992"
    end

    test "encodes very large integer as canonical decimal" do
      assert {:ok, result} = Toon.encode(12_345_678_901_234_567_890)
      assert result == "12345678901234567890"
    end
  end

  # ---------------------------------------------------------------------------
  # Float normalization
  # ---------------------------------------------------------------------------

  describe "float normalization" do
    test "encodes normal float" do
      assert {:ok, "3.14"} = Toon.encode(3.14)
    end

    test "normalizes -0.0 to 0" do
      assert {:ok, "0"} = Toon.encode(-0.0)
    end

    test "normalizes :infinity to null" do
      # Elixir represents infinity as :infinity atom (from :math); encode must map to null
      assert {:ok, "null"} = Toon.encode(:infinity)
    end

    test "normalizes :neg_infinity to null" do
      assert {:ok, "null"} = Toon.encode(:neg_infinity)
    end

    test "normalizes :nan to null" do
      assert {:ok, "null"} = Toon.encode(:nan)
    end
  end

  # ---------------------------------------------------------------------------
  # MapSet normalization (analogous to JS Set)
  # ---------------------------------------------------------------------------

  describe "MapSet normalization (analogous to JS Set)" do
    test "encodes MapSet as sorted list" do
      # MapSet has no defined order; sort before encoding for determinism
      input = MapSet.new(["a", "b", "c"])
      assert {:ok, result} = Toon.encode(input)
      {:ok, decoded} = Toon.decode(result)
      assert Enum.sort(decoded) == ["a", "b", "c"]
    end

    test "encodes empty MapSet as empty array" do
      assert {:ok, "[0]:"} = Toon.encode(MapSet.new())
    end
  end

  # ---------------------------------------------------------------------------
  # DateTime normalization (analogous to JS Date)
  # ---------------------------------------------------------------------------

  describe "DateTime normalization (analogous to JS Date)" do
    test "encodes DateTime as quoted ISO 8601 string via Toon.Encodable" do
      dt = ~U[2025-01-01 00:00:00Z]
      assert {:ok, result} = Toon.encode(dt)
      assert result == ~s("2025-01-01T00:00:00Z")
    end

    test "encodes Date as quoted ISO 8601 string" do
      d = ~D[2025-11-05]
      assert {:ok, result} = Toon.encode(d)
      assert result == ~s("2025-11-05")
    end
  end

  # ---------------------------------------------------------------------------
  # nil normalization
  # ---------------------------------------------------------------------------

  describe "nil normalization" do
    test "encodes nil as null" do
      assert {:ok, "null"} = Toon.encode(nil)
    end
  end

  # ---------------------------------------------------------------------------
  # Toon.Encodable protocol (analogous to toJSON method)
  # ---------------------------------------------------------------------------

  describe "Toon.Encodable protocol (analogous to toJSON method)" do
    test "calls Toon.Encodable.to_toon/1 when implemented" do
      struct = %NormTestStruct{data: "example"}
      assert {:ok, result} = Toon.encode(struct)
      assert result == "info: example"
    end

    test "protocol returning a primitive encodes as primitive" do
      assert {:ok, "custom-string"} = Toon.encode(%NormPrimitiveStruct{value: 42})
    end

    test "protocol returning a list encodes as array" do
      assert {:ok, "[3]: a,b,c"} = Toon.encode(%NormListStruct{items: ["a", "b", "c"]})
    end

    test "protocol applied to nested struct in object" do
      input = %{"nested" => %NormNestedStruct{secret: "hidden"}, "other" => "value"}
      assert {:ok, result} = Toon.encode(input)
      assert result == "nested:\n  public: visible\nother: value"
    end

    test "protocol applied to structs inside array elements" do
      arr = [%NormRowStruct{data: "first"}, %NormRowStruct{data: "second"}]
      assert {:ok, result} = Toon.encode(arr)
      assert result == "[2]{transformed}:\n  first-transformed\n  second-transformed"
    end
  end
end
