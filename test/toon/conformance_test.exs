defmodule Toon.ConformanceTest do
  use ExUnit.Case

  @fixtures_path "test/fixtures"

  # Dynamically generate test cases from JSON fixtures committed at SPEC_COMMIT.
  # @external_resource ensures recompilation when a fixture file changes.
  # Note: adding a NEW fixture file requires `touch test/toon/conformance_test.exs`
  # to force recompilation — Path.wildcard/1 at compile time cannot observe new files.
  for category <- ["decode", "encode"] do
    for fixture_file <- Path.wildcard("#{@fixtures_path}/#{category}/*.json") do
      @external_resource fixture_file
      fixture = File.read!(fixture_file) |> Jason.decode!()

      for test_case <- fixture["tests"] do
        @tag spec_section: test_case["specSection"]
        # Fixtures use "shouldError" key (not "error" — discovered from actual fixture files)
        @test_is_error test_case["shouldError"] == true || test_case["error"] == true
        @test_name "#{Path.basename(fixture_file, ".json")}/#{test_case["name"]}"
        @test_input test_case["input"]
        @test_expected test_case["expected"]
        @test_options test_case["options"]
        # Capture category as a module attribute so it is available inside the test body.
        # @tag category: category cannot be read back inside test/2 via @category.
        @test_category category

        test @test_name do
          if @test_is_error do
            case @test_category do
              "decode" ->
                assert {:error, %Toon.DecodeError{}} = Toon.decode(@test_input)

              "encode" ->
                assert {:error, %Toon.EncodeError{}} = Toon.encode(@test_input)
            end
          else
            opts = build_opts(@test_options, @test_category)

            case @test_category do
              "decode" ->
                assert {:ok, result} = Toon.decode(@test_input, opts)
                assert result == @test_expected

              "encode" ->
                assert {:ok, result} = Toon.encode(@test_input, opts)
                assert result == @test_expected
            end
          end
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Option builders — convert JSON option maps to Elixir keyword lists
  # ---------------------------------------------------------------------------

  defp build_opts(nil, _category), do: []

  defp build_opts(opts_map, "decode") when is_map(opts_map) do
    []
    |> maybe_put(:strict, opts_map["strict"])
    |> maybe_put(:expand_paths, expand_paths_opt(opts_map["expandPaths"]))
  end

  defp build_opts(opts_map, "encode") when is_map(opts_map) do
    []
    |> maybe_put(:indent, opts_map["indent"])
    |> maybe_put(:delimiter, delimiter_opt(opts_map["delimiter"]))
    |> maybe_put(:key_folding, key_folding_opt(opts_map["keyFolding"]))
    |> maybe_put(:flatten_depth, opts_map["flattenDepth"])
  end

  # Fixture delimiter values are the actual character strings: "\t", "|", ","
  defp delimiter_opt(nil), do: nil
  defp delimiter_opt("\t"), do: :tab
  defp delimiter_opt("|"), do: :pipe
  defp delimiter_opt(","), do: :comma
  defp delimiter_opt(other), do: String.to_existing_atom(other)

  defp expand_paths_opt(nil), do: nil
  defp expand_paths_opt("safe"), do: :safe
  defp expand_paths_opt("off"), do: :off

  defp key_folding_opt(nil), do: nil
  defp key_folding_opt("safe"), do: :safe
  defp key_folding_opt("off"), do: :off

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
