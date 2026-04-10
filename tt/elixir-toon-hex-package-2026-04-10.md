# Feature: Elixir TOON Library for Hex.pm

**Status:** 🔴 DRAFT (requires review)
**Priority:** P1 (new library — enables Elixir/Phoenix ecosystem to use TOON for LLM prompts)
**Estimated Effort:** 40 hours
**Date:** 2026-04-10
**Spec Version:** TOON v3.0

## Problem

There is no Elixir implementation of the TOON format (Token-Oriented Object Notation). The
[toon-format/spec](https://github.com/toon-format/spec) lists community implementations for
TypeScript, Python, Go, Rust, and .NET — Elixir is absent.

Elixir is widely used for LLM-adjacent workloads (Phoenix LiveView AI apps, Nx/Bumblebee,
LangChain Elixir). Teams building LLM pipelines in Elixir currently have no native way to
encode JSON data as TOON for prompt construction.

### Evidence

- Reference implementation: [github.com/toon-format/toon](https://github.com/toon-format/toon)
  (TypeScript, MIT license)
- Specification: [github.com/toon-format/spec SPEC.md v3.0](https://github.com/toon-format/spec)
- Language-agnostic conformance fixtures:
  `toon-format/spec/tests/fixtures/{decode,encode}/*.json`
- Fixture format (example from `decode/primitives.json`):
  ```json
  {
    "version": "1.4",
    "category": "decode",
    "tests": [
      { "name": "parses safe unquoted string", "input": "hello", "expected": "hello" }
    ]
  }
  ```

### Current Behavior

No Elixir TOON library exists on Hex.pm.

### Expected Behavior

```elixir
# Encode
Toon.encode(%{
  context: %{task: "Our favorite hikes", location: "Boulder"},
  friends: ["ana", "luis", "sam"],
  hikes: [
    %{id: 1, name: "Blue Lake Trail", distance_km: 7.5, sunny: true},
    %{id: 2, name: "Ridge Overlook", distance_km: 9.2, sunny: false}
  ]
})
# =>
# context:
#   task: Our favorite hikes
#   location: Boulder
# friends[3]: ana,luis,sam
# hikes[2]{id,name,distance_km,sunny}:
#   1,Blue Lake Trail,7.5,true
#   2,Ridge Overlook,9.2,false

# Decode
Toon.decode("""
context:
  task: Our favorite hikes
  location: Boulder
friends[3]: ana,luis,sam
""")
# => %{"context" => %{"task" => "Our favorite hikes", "location" => "Boulder"},
#      "friends" => ["ana", "luis", "sam"]}
```

### Impact

- Enables Elixir LLM applications to reduce token usage by ~40% on uniform structured data
- Provides spec-conformant round-trip encode/decode with language-agnostic test coverage
- Positions the package as the canonical Elixir TOON implementation in the toon-format ecosystem

## Solution

Implement a full TOON v3.0 spec-conformant Elixir library published to Hex.pm, mirroring
the TypeScript reference implementation's architecture.

### Architecture

Port the TypeScript reference implementation module-by-module to idiomatic Elixir:

| TypeScript module           | Elixir module              |
|-----------------------------|----------------------------|
| `src/index.ts`              | `Toon` (public API)        |
| `src/types.ts`              | `Toon.Types` (typespecs)   |
| `src/constants.ts`          | `Toon.Constants`           |
| `src/encode/normalize.ts`   | `Toon.Encoder.Normalize`   |
| `src/encode/encoders.ts`    | `Toon.Encoder`             |
| `src/encode/primitives.ts`  | `Toon.Encoder.Primitives`  |
| `src/encode/folding.ts`     | `Toon.Encoder.Folding`     |
| `src/encode/replacer.ts`    | `Toon.Encoder.Replacer`    |
| `src/decode/scanner.ts`     | `Toon.Decoder.Scanner`     |
| `src/decode/parser.ts`      | `Toon.Decoder.Parser`      |
| `src/decode/decoders.ts`    | `Toon.Decoder`             |
| `src/decode/event-builder.ts` | `Toon.Decoder.EventBuilder` |
| `src/decode/expand.ts`      | `Toon.Decoder.Expand`      |
| `src/decode/validation.ts`  | `Toon.Decoder.Validation`  |
| `src/shared/string-utils.ts` | `Toon.StringUtils`        |
| `src/shared/literal-utils.ts` | `Toon.LiteralUtils`      |
| `src/shared/validation.ts`  | `Toon.Validation`          |

**Elixir-specific adaptations:**
- No async streaming (Elixir has `Stream` for lazy evaluation instead of async iterables)
- Elixir maps are used instead of JS objects; map key ordering follows insertion order via `Map`
- Atom keys normalized to strings in encoder
- `nil` → `null`, `true`/`false` → booleans (already matching)
- Streaming encode via `Stream.resource/3` or generator function returning `Enumerable`
- Streaming decode via `Stream.resource/3` over lines

### Implementation

**Step 1: Mix project scaffold**

```bash
mix new elixir_toon --module Toon
```

`mix.exs`:
```elixir
defmodule Toon.MixProject do
  use Mix.Project

  def project do
    [
      app: :toon,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Token-Oriented Object Notation (TOON) encoder/decoder for Elixir",
      package: package(),
      docs: docs(),
      name: "Toon",
      source_url: "https://github.com/USERNAME/elixir-toon"
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:jason, "~> 1.4", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/USERNAME/elixir-toon",
        "Spec" => "https://github.com/toon-format/spec",
        "Reference Implementation" => "https://github.com/toon-format/toon"
      },
      maintainers: ["..."]
    ]
  end

  defp docs do
    [
      main: "Toon",
      extras: ["README.md"]
    ]
  end
end
```

**Step 2: Constants and Types**

`lib/toon/constants.ex`:
```elixir
defmodule Toon.Constants do
  @type delimiter :: ?,  | ?\t | ?|
  @type delimiter_key :: :comma | :tab | :pipe

  @default_delimiter ?,

  def default_delimiter, do: @default_delimiter
  def delimiters, do: %{comma: ?,, tab: ?\t, pipe: ?|}
end
```

`lib/toon/types.ex` — typespecs mirroring TypeScript types:
```elixir
@type json_primitive :: String.t() | number() | boolean() | nil
@type json_object :: %{String.t() => json_value()}
@type json_array :: [json_value()]
@type json_value :: json_primitive() | json_object() | json_array()

@type encode_options :: %{
  optional(:indent) => pos_integer(),
  optional(:delimiter) => :comma | :tab | :pipe,
  optional(:key_folding) => :off | :safe,
  optional(:flatten_depth) => pos_integer() | :infinity,
  optional(:replacer) => (String.t(), json_value(), [String.t() | integer()] -> term())
}

@type decode_options :: %{
  optional(:indent) => pos_integer(),
  optional(:strict) => boolean(),
  optional(:expand_paths) => :off | :safe
}
```

**Step 3: Encoder — Normalize**

`lib/toon/encoder/normalize.ex`:
- Convert Elixir terms to the JSON data model
- Atoms → strings (except `nil`, `true`, `false`)
- Atom-keyed maps → string-keyed maps
- `NaN`, `±Infinity` → `nil`
- Structs → call `Jason.Encoder` protocol or `Map.from_struct/1`
- Tuples → lists

**Step 4: Encoder — String Utils**

`lib/toon/string_utils.ex` — quoting rules from §7.2:
```elixir
defmodule Toon.StringUtils do
  @spec needs_quoting?(String.t(), integer()) :: boolean()
  def needs_quoting?(str, active_delimiter) do
    str == "" or
    has_leading_trailing_whitespace?(str) or
    str in ["true", "false", "null"] or
    numeric_like?(str) or
    contains_special_chars?(str, active_delimiter) or
    starts_with_hyphen?(str)
  end

  @spec escape(String.t()) :: String.t()
  def escape(str) do
    # Escape: \\ → \\\\, " → \", \n → \\n, \r → \\r, \t → \\t
  end
end
```

**Step 5: Encoder — Core**

`lib/toon/encoder.ex`:
- `encode_value/3` — dispatch on type
- `encode_object/3` — key: value lines with indentation
- `encode_array/3` — determine form:
  - Primitive array: `key[N]: v1,v2,v3`
  - Tabular uniform array: `key[N]{f1,f2}: \n  row1,row2`
  - Expanded list: `key[N]:\n  - ...`
- `is_uniform?/1` — check if all items are objects with same primitive-value keys
- Key folding (`key_folding: :safe`): collapse single-key object chains into dotted paths

**Step 6: Decoder — Scanner**

`lib/toon/decoder/scanner.ex`:
- Parse a line into `%ParsedLine{raw, depth, indent, content, line_number}`
- Detect array headers via regex matching §6 grammar
- Extract: key, length, delimiter, fields list

**Step 7: Decoder — Parser + Event Builder**

`lib/toon/decoder/parser.ex`:
- Stateful parser consuming `ParsedLine` stream
- Emit `JsonStreamEvent` structs:
  - `%{type: :start_object}`
  - `%{type: :end_object}`
  - `%{type: :start_array, length: n}`
  - `%{type: :end_array}`
  - `%{type: :key, key: str}`
  - `%{type: :primitive, value: val}`
- Handle: root form detection (§5), tabular rows, list items, nested objects

`lib/toon/decoder/event_builder.ex`:
- Consume event stream, build final `json_value()`

**Step 8: Decoder — Validation (Strict Mode)**

`lib/toon/decoder/validation.ex`:
- Enforce array length counts
- Validate indentation consistency
- Reject invalid escape sequences
- Return `{:error, reason}` tuple on violations

**Step 9: Public API**

`lib/toon.ex`:
```elixir
defmodule Toon do
  @spec encode(term(), encode_options()) :: String.t()
  def encode(input, opts \\ %{}) do
    input |> encode_lines(opts) |> Enum.join("\n")
  end

  @spec decode(String.t(), decode_options()) :: {:ok, json_value()} | {:error, term()}
  def decode(input, opts \\ %{}) do
    input |> String.split("\n") |> decode_from_lines(opts)
  end

  @spec encode_lines(term(), encode_options()) :: Enumerable.t()
  def encode_lines(input, opts \\ %{})

  @spec decode_from_lines(Enumerable.t(), decode_options()) :: {:ok, json_value()} | {:error, term()}
  def decode_from_lines(lines, opts \\ %{})

  @spec decode_stream(Enumerable.t(), decode_options()) :: Enumerable.t()
  def decode_stream(lines, opts \\ %{})
end
```

**Step 10: Conformance Tests**

Download and integrate all 22 JSON fixture files from
`toon-format/spec/tests/fixtures/{decode,encode}/*.json` as ExUnit test cases.

`test/toon/conformance_test.exs`:
```elixir
defmodule Toon.ConformanceTest do
  use ExUnit.Case

  @fixtures_path "test/fixtures"

  # Dynamically generate test cases from JSON fixtures
  for category <- ["decode", "encode"] do
    for fixture_file <- Path.wildcard("#{@fixtures_path}/#{category}/*.json") do
      fixture = File.read!(fixture_file) |> Jason.decode!()
      for test_case <- fixture["tests"] do
        @tag spec_section: test_case["specSection"]
        test "#{category}/#{fixture["category"]}: #{test_case["name"]}" do
          # ...
        end
      end
    end
  end
end
```

### Files to Create

```
mix.exs
lib/
  toon.ex                         # Public API: encode/2, decode/2, encode_lines/2, decode_from_lines/2, decode_stream/2
  toon/
    constants.ex                  # Delimiters, defaults
    types.ex                      # Typespecs
    string_utils.ex               # Quoting, escaping (§7.1, §7.2)
    literal_utils.ex              # Number/bool/null literal parsing
    validation.ex                 # Shared validation helpers
    encoder.ex                    # Core encoder (dispatch, objects, arrays)
    encoder/
      normalize.ex                # Host-type normalization (§3)
      primitives.ex               # Primitive encoding
      folding.ex                  # Key folding (§13.4)
      replacer.ex                 # Replacer callback support
    decoder.ex                    # Core decoder entry points
    decoder/
      scanner.ex                  # Line tokenizer, header parsing
      parser.ex                   # Structural event parser
      event_builder.ex            # Build value from events
      expand.ex                   # Path expansion (§13.4)
      validation.ex               # Strict-mode validation (§14)
test/
  toon_test.exs                   # Smoke tests for public API
  toon/
    conformance_test.exs          # All spec fixtures
    encoder_test.exs              # Unit tests for encoder
    decoder_test.exs              # Unit tests for decoder
    string_utils_test.exs         # Quoting/escaping tests
  fixtures/
    decode/                       # Copied from toon-format/spec
    encode/                       # Copied from toon-format/spec
README.md
.formatter.exs
.gitignore
```

## Testing

### Conformance Tests (Priority 1)

Use the 22 language-agnostic JSON fixtures from `toon-format/spec/tests/fixtures/`:

**Decode fixtures (13 files):**
- `arrays-nested.json`, `arrays-primitive.json`, `arrays-tabular.json`
- `blank-lines.json`, `delimiters.json`, `indentation-errors.json`
- `numbers.json`, `objects.json`, `path-expansion.json`
- `primitives.json`, `root-form.json`, `validation-errors.json`, `whitespace.json`

**Encode fixtures (9 files):**
- `arrays-nested.json`, `arrays-objects.json`, `arrays-primitive.json`, `arrays-tabular.json`
- `delimiters.json`, `key-folding.json`, `objects.json`, `primitives.json`, `whitespace.json`

### Unit Tests

```elixir
describe "Toon.encode/2" do
  test "encodes flat object" do
    assert Toon.encode(%{"name" => "Alice", "age" => 30}) == "name: Alice\nage: 30"
  end

  test "encodes uniform array as tabular" do
    input = %{"users" => [%{"id" => 1, "name" => "Alice"}, %{"id" => 2, "name" => "Bob"}]}
    assert Toon.encode(input) == "users[2]{id,name}:\n  1,Alice\n  2,Bob"
  end

  test "encodes primitive array inline" do
    assert Toon.encode(%{"tags" => ["a", "b", "c"]}) == "tags[3]: a,b,c"
  end

  test "normalizes atom keys" do
    assert Toon.encode(%{name: "Alice"}) == "name: Alice"
  end

  test "quotes strings that need quoting" do
    assert Toon.encode(%{"val" => "true"}) == ~s(val: "true")
  end
end

describe "Toon.decode/2" do
  test "decodes flat object" do
    assert {:ok, %{"name" => "Alice", "age" => 30}} = Toon.decode("name: Alice\nage: 30")
  end

  test "decodes tabular array" do
    input = "users[2]{id,name}:\n  1,Alice\n  2,Bob"
    assert {:ok, %{"users" => [%{"id" => 1, "name" => "Alice"}, %{"id" => 2, "name" => "Bob"}]}} =
      Toon.decode(input)
  end

  test "strict mode raises on length mismatch" do
    assert {:error, _} = Toon.decode("tags[3]: a,b", strict: true)
  end

  test "decodes numbers correctly" do
    assert {:ok, 42} = Toon.decode("42")
    assert {:ok, -3.14} = Toon.decode("-3.14")
    assert {:ok, "05"} = Toon.decode("05")  # leading zero → string
  end
end
```

### Manual Testing

1. `mix deps.get && mix test` — all conformance fixtures pass
2. `mix test --only spec_section:9.3` — tabular array tests
3. `mix dialyzer` — no type errors
4. `mix hex.build` — package builds successfully
5. Install in iex: `iex -S mix` and smoke-test encode/decode round-trip

## Implementation Workflow

All commits reference the main tracking issue:

```bash
git commit -m "chore: init mix project (#1)"
git commit -m "feat(constants): add delimiter types and defaults (#1)"
git commit -m "feat(encoder): implement normalize and string utils (#1)"
git commit -m "feat(encoder): implement core encode/object/array (#1)"
git commit -m "feat(encoder): implement key folding (#1)"
git commit -m "feat(decoder): implement scanner and header parser (#1)"
git commit -m "feat(decoder): implement event parser and builder (#1)"
git commit -m "feat(decoder): implement strict-mode validation (#1)"
git commit -m "feat(decoder): implement path expansion (#1)"
git commit -m "feat(api): implement public Toon module (#1)"
git commit -m "test: add conformance test harness (#1)"
git commit -m "test: download and integrate spec fixtures (#1)"
git commit -m "docs: write README and module docs (#1)"
git commit -m "chore: configure Hex.pm package metadata (#1)"
```

## Migration Strategy

No migration needed — this is a new package from scratch.

## Rollback Plan

Rollback: standard git revert (new package, no breaking changes to existing systems).

## Documentation

**README.md** structure:
1. **What is TOON?** — link to spec, benchmark summary
2. **Installation** — `{:toon, "~> 0.1"}` in mix.exs
3. **Quick Start** — encode/decode examples
4. **API Reference** — all public functions with options
5. **Format Overview** — key TOON syntax examples
6. **Conformance** — link to spec fixtures, how to verify
7. **License** — MIT

**ExDoc** inline docs on every public function in `lib/toon.ex`.

## Acceptance Criteria

- [ ] `mix test` passes all 22 conformance fixture files (decode + encode)
- [ ] `Toon.encode/2` round-trips with `Toon.decode/2` for all spec examples
- [ ] Strict mode (`strict: true`) correctly rejects all invalid inputs from `validation-errors.json`
- [ ] `key_folding: :safe` + `expand_paths: :safe` round-trip losslessly
- [ ] Streaming encode via `encode_lines/2` returns correct `Enumerable`
- [ ] Streaming decode via `decode_stream/2` returns correct `Enumerable` of events
- [ ] Atom-keyed maps normalized correctly in encoder
- [ ] Number canonicalization: trailing zeros stripped, exponent forms accepted on decode
- [ ] `mix dialyzer` runs clean
- [ ] `mix hex.build` succeeds
- [ ] README complete with installation, quick start, API reference
- [ ] Code review passed

## Notes

- **No existing Elixir TOON library** on Hex.pm (verified April 2026)
- **Spec version:** TOON v3.0 (2025-11-24) — stable for implementation
- **License:** MIT (matches reference implementation)
- **Elixir minimum version:** 1.15 (for improved pattern matching and Stream improvements)
- **Key difference from TS:** Elixir has no `async`/`await`; streaming is via `Stream` module
- **Key difference from TS:** Elixir maps do not preserve insertion order by default in small
  maps; use `:maps.from_list/1` with ordered list for deterministic output
- **Atom key normalization:** `encode(%{name: "Alice"})` must work — convert atom keys to strings
- The spec fixtures use `"specSection"` field for cross-referencing; tag ExUnit tests with
  `@tag spec_section: ...` for selective test runs

## Follow-up Tasks

1. Submit to `toon-format` organization as official Elixir implementation
2. Add `encode!/2` and `decode!/2` bang variants that raise on error
3. Consider `Toon.Sigil` (`~TOON`) for compile-time TOON decoding in tests
4. Benchmark vs Jason for LLM prompt construction workflows
5. Optional: `Toon.Encoder` protocol (similar to Jason.Encoder) for custom struct encoding
