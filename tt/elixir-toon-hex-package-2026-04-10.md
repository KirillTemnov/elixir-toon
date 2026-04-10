# Feature: Elixir TOON Library for Hex.pm

**Status:** 🔴 DRAFT (requires review)
**Priority:** P1 (new library — enables Elixir/Phoenix ecosystem to use TOON for LLM prompts)
**Estimated Effort:** 40 hours
**Date:** 2026-04-10
**GitHub Issue:** #1
**Spec Version:** TOON v3.0

## Review Panel Discussion

### Round 0: CLAUDE.md Compliance Check
**Reviewer:** @compliance-auditor
**Timestamp:** 2026-04-10
**Status:** ⚠️ WARNINGS — 1 VIOLATION FOUND AND FIXED

**Compliance Scan Results:**

**✅ COMPLIANT:**
- English in all code blocks and inline comments — no non-English text found in any code block
- No Russian text anywhere in the document (`grep [а-яА-Я]` → 0 matches)
- TZ written in English (global.md permits Russian or English for `/tt` specs)
- Atomic commits with issue references — Implementation Workflow lists 14 granular commits, each referencing `#1`
- Conventional Commits format — all commit messages use `feat:`, `chore:`, `test:`, `docs:` prefixes
- GitHub Issue reference present — `**GitHub Issue:** #1` in the header
- Elixir naming conventions correct — Modules PascalCase (`Toon`, `Toon.Constants`, `Toon.Encoder.Normalize`), functions snake_case (`encode/2`, `decode/2`, `needs_quoting?/2`), files snake_case (`constants.ex`, `string_utils.ex`)
- Error handling — `decode/2` returns `{:ok, json_value()} | {:error, term()}` tuples throughout
- Tests in English — all `describe`/`test` blocks use English names and assertions

**❌ VIOLATIONS (Must fix):**
1. **VIOLATION: File endings with newline**
   - **Location:** Notes section — implementation guidance
   - **Problem:** global.md mandates `\n` at end of every file, but the TZ contains no instruction to developers to add a trailing newline to each generated `.ex` file. Without this note implementers may skip it.
   - **Required Fix:** Add explicit note in the Notes section: all source files must end with a newline character (`\n`).
   - **Action:** FIXED

**Changes Made:**
- Added note to Notes section: "All source files must end with a trailing newline (`\n`), per project formatting rules."

---

### Round 1a: Architecture Review (Independent)
**Reviewer:** @architecture-designer-alpha
**Timestamp:** 2026-04-10
**Status:** ⚠️ WARNINGS — multiple architectural concerns, several fixed in-place

**Findings:**

- ✅ LGTM: Module decomposition mirroring the TypeScript reference is reasonable and
  keeps the port traceable. Encoder/Decoder split is clean. Symmetric `Encoder.Folding` ↔
  `Decoder.Expand` pairing is sound.
- ✅ LGTM: No supervision tree — correct choice for a pure library. No GenServer needed.
- ✅ LGTM: Conformance-first test strategy with language-agnostic fixtures is the right
  approach for a spec-conformant port.
- ✅ LGTM: Jason is correctly scoped as test-only (`only: :test`) in `mix.exs`.

- ❌ ISSUE (FIXED): **`Jason.Encoder` protocol referenced in runtime normalize path
  while Jason is a test-only dep.** Step 3 says "Structs → call `Jason.Encoder` protocol or
  `Map.from_struct/1`". This creates a hidden runtime dependency on Jason. Fix: define a
  native `Toon.Encoder` protocol (similar to `Jason.Encoder`) as part of the initial design,
  not as a follow-up task. Structs default to `Map.from_struct/1` when no protocol impl exists.

- ❌ ISSUE (FIXED): **Options as maps are unidiomatic in Elixir.** The TZ uses
  `opts \\ %{}` and `@type encode_options :: %{optional(:indent) => ...}`. Standard Elixir
  libraries (Jason, Ecto, Phoenix, Plug) use keyword lists: `opts \\ []`. Callers expect
  `Toon.encode(value, indent: 4, delimiter: :tab)`, not `Toon.encode(value, %{indent: 4})`.
  Fix: switch all option parameters to keyword lists; validate via pattern matching or
  `Keyword.validate!/2` (available since Elixir 1.13).

- ❌ ISSUE (FIXED): **Map key ordering is a correctness problem, not just a note.**
  Elixir maps do NOT preserve insertion order — small maps (≤32 keys) are sorted by term
  order, large maps use HAMT. The TypeScript reference relies on JS object insertion order
  for deterministic output. This must be an explicit architectural decision in the Solution,
  not a trailing note. Fix: document the deterministic ordering contract — accept
  `Keyword.t()` and lists of `{key, value}` tuples as ordered alternatives; for plain maps,
  use sorted keys for deterministic (but differently-ordered) output. Conformance fixtures
  must be reviewed to confirm this doesn't break round-trip.

- ❌ ISSUE (FIXED): **Error type `{:error, term()}` is too loose for a library API.**
  Users of `Toon.decode/2` need structured errors to report line numbers and reasons.
  Fix: introduce `Toon.DecodeError` struct with `:line`, `:column`, `:reason`, `:message`
  fields. Return `{:error, %Toon.DecodeError{...}}`.

- ❌ ISSUE (FIXED): **`decode_stream/2` semantics are ambiguous.** Returning "Enumerable
  of events" leaks internal parser events into the public API. A streaming decoder should
  either (a) decode a sequence of top-level TOON documents from a chunked source, or
  (b) decode a single document from a lazy line source. Option (b) is more useful and
  aligns with `decode_from_lines/2` which the TZ already defines. Fix: drop
  `decode_stream/2` from the public API for v0.1; defer streaming iteration to a follow-up
  once a concrete use case emerges. Keep `decode_from_lines/2` which accepts any
  `Enumerable.t()` of lines — this already covers the lazy-source case.

- ⚠️ CONCERN (FIXED): **Separate `Toon.Types` module is a TypeScript-ism.** Elixir places
  `@type` declarations in the owning module. A dedicated types module splits the public
  contract across files for no benefit. Fix: move `@type` declarations inline into `Toon`
  (public types) and into the modules that own each internal type.

- ⚠️ CONCERN (FIXED): **Internal helpers leak into the public namespace.**
  `Toon.StringUtils`, `Toon.LiteralUtils`, `Toon.Validation` sit at the top level alongside
  the public `Toon` module, implying they are part of the public API. Fix: mark them
  `@moduledoc false` OR move them under `Toon.Internal.*`. The TZ should state this
  explicitly.

- ⚠️ CONCERN (FIXED): **Name clash: two `Validation` modules.** `Toon.Validation` (shared
  literal validation) and `Toon.Decoder.Validation` (strict-mode checks) invite confusion.
  Fix: rename the strict-mode module to `Toon.Decoder.StrictMode` to reflect its purpose.

- ⚠️ CONCERN (FIXED): **Acceptance criterion requires Dialyzer but no Dialyzer dep.**
  `mix dialyzer` cannot run without `:dialyxir` in deps. Fix: add `{:dialyxir, "~> 1.4",
  only: [:dev], runtime: false}` to `mix.exs` deps.

- ⚠️ CONCERN (FIXED): **`start_permanent` is dead code in a pure library.** Without an
  `application` callback, `start_permanent` has no effect. It's boilerplate noise from
  `mix new --sup`. Fix: remove from `mix.exs`.

- ⚠️ CONCERN: **Input-type contract for `encode/2` is underspecified.** The TZ does not
  enumerate what Elixir terms are accepted: map, keyword list, list of tuples, struct,
  number, binary, atom, tuple, nil. This must be listed explicitly to drive Normalize
  module tests. (Partially addressed by new input-ordering section; full enumeration left
  to implementer.)

- ⚠️ CONCERN: **Compile-time fixture generation needs `@external_resource`.** The
  `conformance_test.exs` dynamic `for` loop reading fixture JSON at compile time will not
  trigger recompilation when fixtures change unless each fixture file is registered as an
  external resource. Fix: add `@external_resource` for each fixture path. Note added to
  testing section.

- 💡 SUGGESTION: **Consider `NimbleOptions`** for option validation. It produces
  self-documenting, typed option specs and good error messages. Adds one dep but pays for
  itself on public APIs. Left as a non-blocking suggestion.

- 💡 SUGGESTION: **Add `encode!/2` and `decode!/2` bang variants to v0.1**, not as a
  follow-up. They are idiomatic in Elixir (`Jason.encode!/1`, `File.read!/1`) and cost
  ~6 lines each. Moving from Follow-up → Solution.

- 💡 SUGGESTION: **Drop the redundant `encode_lines/2`** unless there's a concrete
  streaming use case. TOON documents are typically small (LLM prompts ≤ 10KB). Lazy
  encoding adds implementation complexity (`Stream.resource/3`) for unclear benefit.
  Flagged — decision left to implementer.

**Changes Made:**
1. Reworked Architecture section: added explicit "Key architectural decisions" subsection
   covering Elixir protocol, options style, key ordering, error types.
2. Added `Toon.Encoder` protocol to module list and removed `Jason.Encoder` reference
   from the Normalize step.
3. Changed all options parameters from maps (`%{}`) to keyword lists (`[]`) in code
   samples.
4. Added `Toon.DecodeError` struct to Files to Create and updated decode return types
   throughout.
5. Removed `decode_stream/2` from the public API; kept `decode_from_lines/2` which
   already handles lazy line sources.
6. Removed `lib/toon/types.ex` from Files to Create; `@type` declarations move into
   owning modules.
7. Renamed `Toon.Decoder.Validation` → `Toon.Decoder.StrictMode`.
8. Marked `Toon.StringUtils`, `Toon.LiteralUtils`, `Toon.Validation` as
   `@moduledoc false` (internal) in the module list.
9. Added `:dialyxir` to `mix.exs` dev deps.
10. Removed `start_permanent` from `mix.exs`.
11. Moved `encode!/2` and `decode!/2` from Follow-up to Solution.
12. Moved `Toon.Encoder` protocol from Follow-up to Solution.
13. Added `@external_resource` note to conformance test section.
14. Added "Key ordering contract" subsection to Solution documenting the
    deterministic-ordering strategy.
15. Updated acceptance criteria to reflect new API surface.

---

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

Port the TypeScript reference implementation module-by-module to idiomatic Elixir.
Internal helpers are marked `@moduledoc false` and are not part of the public contract.

| TypeScript module             | Elixir module                   | Visibility |
|-------------------------------|---------------------------------|------------|
| `src/index.ts`                | `Toon` (public API)             | public     |
| —                             | `Toon.Encoder` (protocol)       | public     |
| —                             | `Toon.DecodeError` (exception)  | public     |
| `src/constants.ts`            | `Toon.Constants`                | internal   |
| `src/encode/normalize.ts`     | `Toon.Encoder.Normalize`        | internal   |
| `src/encode/encoders.ts`      | `Toon.Encoder.Core`             | internal   |
| `src/encode/primitives.ts`    | `Toon.Encoder.Primitives`       | internal   |
| `src/encode/folding.ts`       | `Toon.Encoder.Folding`          | internal   |
| `src/encode/replacer.ts`      | `Toon.Encoder.Replacer`         | internal   |
| `src/decode/scanner.ts`       | `Toon.Decoder.Scanner`          | internal   |
| `src/decode/parser.ts`        | `Toon.Decoder.Parser`           | internal   |
| `src/decode/decoders.ts`      | `Toon.Decoder.Core`             | internal   |
| `src/decode/event-builder.ts` | `Toon.Decoder.EventBuilder`     | internal   |
| `src/decode/expand.ts`        | `Toon.Decoder.Expand`           | internal   |
| `src/decode/validation.ts`    | `Toon.Decoder.StrictMode`       | internal   |
| `src/shared/string-utils.ts`  | `Toon.StringUtils`              | internal   |
| `src/shared/literal-utils.ts` | `Toon.LiteralUtils`             | internal   |
| `src/shared/validation.ts`    | `Toon.Validation`               | internal   |

> Note: `src/types.ts` has no direct Elixir equivalent — typespecs live in the module
> that owns each concept (idiomatic Elixir), not in a dedicated types module.

**Key architectural decisions (Elixir-specific adaptations):**

1. **Options are keyword lists, not maps.** All public functions accept `opts \\ []`.
   Example: `Toon.encode(value, indent: 4, delimiter: :tab)`. Validated with
   `Keyword.validate!/2`. This matches Jason/Ecto/Phoenix conventions.

2. **Custom struct encoding via a `Toon.Encoder` protocol** (not `Jason.Encoder`).
   Modeled after `Jason.Encoder`: consumers implement `Toon.Encoder` for their structs
   to control normalization. Default behavior for any `struct` without an impl is
   `Map.from_struct/1 |> Map.drop([:__struct__, :__meta__])`. This keeps Jason as a
   test-only dependency.

3. **Structured decode errors.** `Toon.decode/2` returns
   `{:ok, json_value()} | {:error, Toon.DecodeError.t()}`. `Toon.DecodeError` is a
   struct with `:line`, `:column`, `:reason`, `:message` fields and implements
   `Exception` so it can be raised by `decode!/2`.

4. **Key ordering contract.** Elixir maps do NOT preserve insertion order. To give
   callers deterministic output that matches the order they care about, `encode/2`
   accepts three container shapes for ordered objects:
   - `map()` — keys are encoded in sorted order (deterministic but alphabetized)
   - `Keyword.t()` — keys are encoded in the list order (callers use this for control)
   - `[{binary() | atom(), value}]` — same as keyword but allows binary keys
   When an object reaches the encoder via any of the above, it produces stable output.
   Atom keys are normalized to strings.

5. **No async; streaming via `Stream`.** `encode/2` produces a complete string.
   `encode_lines/2` returns an `Enumerable.t()` of line binaries built with
   `Stream.resource/3` for callers that need to pipe into `IO.stream/2` or a socket.
   `decode_from_lines/2` accepts an `Enumerable.t()` of line binaries (typically from
   `File.stream!/1` or `IO.stream/2`) and returns `{:ok, value} | {:error, error}`.
   A lazy per-event `decode_stream/2` is **not** included in v0.1 — the use case is
   unclear and it would leak parser internals into the public API.

6. **Bang variants in v0.1.** `encode!/2` and `decode!/2` are idiomatic Elixir
   (`Jason.encode!/1`, `File.read!/1`) and are included from the first release.
   They raise `Toon.DecodeError` / `Toon.EncodeError` on failure.

7. **Atom/literal normalization.** `nil` → `null`; `true`/`false` stay as booleans;
   other atoms → strings; tuples → lists; structs via protocol or `Map.from_struct/1`;
   `NaN`, `±Infinity` (`:nan`, `:infinity`, `:neg_infinity`) → `nil` per spec §3.

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
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
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

**Step 2: Constants, typespecs, and error types**

`lib/toon/constants.ex`:
```elixir
defmodule Toon.Constants do
  @moduledoc false
  @type delimiter :: ?, | ?\t | ?|
  @type delimiter_key :: :comma | :tab | :pipe

  @default_delimiter ?,

  def default_delimiter, do: @default_delimiter
  def delimiters, do: %{comma: ?,, tab: ?\t, pipe: ?|}
end
```

Public typespecs live inside `lib/toon.ex` (no separate `Toon.Types` module):
```elixir
# lib/toon.ex
@type json_primitive :: String.t() | number() | boolean() | nil
@type json_object :: %{String.t() => json_value()}
@type json_array :: [json_value()]
@type json_value :: json_primitive() | json_object() | json_array()

@type encode_opts :: [
  indent: pos_integer(),
  delimiter: :comma | :tab | :pipe,
  key_folding: :off | :safe,
  flatten_depth: pos_integer() | :infinity,
  replacer: (String.t(), json_value(), [String.t() | integer()] -> term())
]

@type decode_opts :: [
  indent: pos_integer(),
  strict: boolean(),
  expand_paths: :off | :safe
]
```

`lib/toon/decode_error.ex`:
```elixir
defmodule Toon.DecodeError do
  @moduledoc """
  Raised or returned when `Toon.decode/2` encounters malformed input.
  """
  defexception [:line, :column, :reason, :message]

  @type t :: %__MODULE__{
          line: pos_integer() | nil,
          column: pos_integer() | nil,
          reason: atom(),
          message: String.t()
        }
end
```

`lib/toon/encode_error.ex`:
```elixir
defmodule Toon.EncodeError do
  @moduledoc """
  Raised by `Toon.encode!/2` when the input cannot be normalized to the TOON data model.
  """
  defexception [:reason, :message, :path]

  @type t :: %__MODULE__{
          reason: atom(),
          message: String.t(),
          path: [String.t() | non_neg_integer()]
        }
end
```

`lib/toon/encoder_protocol.ex` — user-extensible struct encoding:
```elixir
defprotocol Toon.Encoder do
  @moduledoc """
  Protocol for converting custom Elixir terms (typically structs) into the TOON
  data model. Modeled after `Jason.Encoder`. Implementations must return a value
  that is itself encodable (map, list, keyword, primitive).
  """
  @fallback_to_any true
  @spec to_toon(term()) :: term()
  def to_toon(value)
end

defimpl Toon.Encoder, for: Any do
  def to_toon(%_{} = struct), do: struct |> Map.from_struct() |> Map.drop([:__meta__])
  def to_toon(other), do: other
end
```

**Step 3: Encoder — Normalize**

`lib/toon/encoder/normalize.ex` (`@moduledoc false`):
- Convert Elixir terms to the TOON/JSON data model
- Atoms → strings (except `nil`, `true`, `false`)
- Atom-keyed maps → string-keyed maps
- Keyword lists with unique atom keys → ordered string-keyed objects
- List of `{binary, value}` tuples → ordered string-keyed objects
- `NaN`, `±Infinity` (`:nan`, `:infinity`, `:neg_infinity`) → `nil` per spec §3
- Structs → `Toon.Encoder.to_toon/1` protocol dispatch (fallback: `Map.from_struct/1`)
- Tuples → lists
- Plain maps → encoded in sorted-key order (deterministic but alphabetized); callers
  that need a specific order must pass a keyword list or tuple list instead

**Step 4: Encoder — String Utils**

`lib/toon/string_utils.ex` (`@moduledoc false`) — quoting rules from §7.2:
```elixir
defmodule Toon.StringUtils do
  @moduledoc false
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

**Step 8: Decoder — Strict Mode**

`lib/toon/decoder/strict_mode.ex` (`@moduledoc false`, renamed from `Validation` to avoid
name clash with `Toon.Validation`):
- Enforce array length counts
- Validate indentation consistency
- Reject invalid escape sequences
- Return `{:error, %Toon.DecodeError{}}` tuple on violations with line/column set

**Step 9: Public API**

`lib/toon.ex`:
```elixir
defmodule Toon do
  @moduledoc """
  Token-Oriented Object Notation (TOON) encoder/decoder for Elixir.
  Spec-conformant with TOON v3.0.
  """

  alias Toon.{DecodeError, EncodeError}

  # Option keys validated with Keyword.validate!/2 at each entry point.
  # Defaults: indent: 2, delimiter: :comma, key_folding: :off,
  #           flatten_depth: :infinity, strict: false, expand_paths: :off

  @spec encode(term(), encode_opts()) :: String.t()
  def encode(input, opts \\ []) do
    opts = Keyword.validate!(opts, [:indent, :delimiter, :key_folding, :flatten_depth, :replacer])
    input |> encode_lines(opts) |> Enum.join("\n")
  end

  @spec encode!(term(), encode_opts()) :: String.t()
  def encode!(input, opts \\ []), do: encode(input, opts)

  @spec decode(String.t(), decode_opts()) :: {:ok, json_value()} | {:error, DecodeError.t()}
  def decode(input, opts \\ []) when is_binary(input) do
    opts = Keyword.validate!(opts, [:indent, :strict, :expand_paths])
    input |> String.split("\n") |> decode_from_lines(opts)
  end

  @spec decode!(String.t(), decode_opts()) :: json_value()
  def decode!(input, opts \\ []) do
    case decode(input, opts) do
      {:ok, value} -> value
      {:error, %DecodeError{} = err} -> raise err
    end
  end

  @spec encode_lines(term(), encode_opts()) :: Enumerable.t()
  def encode_lines(input, opts \\ [])

  @spec decode_from_lines(Enumerable.t(), decode_opts()) ::
          {:ok, json_value()} | {:error, DecodeError.t()}
  def decode_from_lines(lines, opts \\ [])
end
```

> Note: `decode_stream/2` is intentionally **not** exposed in v0.1. Streaming use cases
> are covered by `decode_from_lines/2` accepting any `Enumerable.t()` of line binaries
> (e.g. `File.stream!("data.toon") |> Toon.decode_from_lines()`). A lazy per-event
> stream can be added in a follow-up once a concrete use case emerges.

**Step 10: Conformance Tests**

Download and integrate all 22 JSON fixture files from
`toon-format/spec/tests/fixtures/{decode,encode}/*.json` as ExUnit test cases.

`test/toon/conformance_test.exs`:
```elixir
defmodule Toon.ConformanceTest do
  use ExUnit.Case

  @fixtures_path "test/fixtures"

  # Dynamically generate test cases from JSON fixtures.
  # @external_resource ensures recompilation when fixtures change.
  for category <- ["decode", "encode"] do
    for fixture_file <- Path.wildcard("#{@fixtures_path}/#{category}/*.json") do
      @external_resource fixture_file
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
  toon.ex                         # Public API: encode/2, encode!/2, decode/2, decode!/2,
                                  #             encode_lines/2, decode_from_lines/2
  toon/
    decode_error.ex               # Public: %Toon.DecodeError{} exception
    encode_error.ex               # Public: %Toon.EncodeError{} exception
    encoder_protocol.ex           # Public: Toon.Encoder protocol (to_toon/1)
    constants.ex                  # @moduledoc false - delimiters, defaults
    string_utils.ex               # @moduledoc false - quoting/escaping (§7.1, §7.2)
    literal_utils.ex              # @moduledoc false - number/bool/null literal parsing
    validation.ex                 # @moduledoc false - shared literal validation
    encoder/
      core.ex                     # @moduledoc false - dispatch, objects, arrays
      normalize.ex                # @moduledoc false - host-type normalization (§3)
      primitives.ex               # @moduledoc false - primitive encoding
      folding.ex                  # @moduledoc false - key folding (§13.4)
      replacer.ex                 # @moduledoc false - replacer callback support
    decoder/
      core.ex                     # @moduledoc false - decoder entry points
      scanner.ex                  # @moduledoc false - line tokenizer, header parsing
      parser.ex                   # @moduledoc false - structural event parser
      event_builder.ex            # @moduledoc false - build value from events
      expand.ex                   # @moduledoc false - path expansion (§13.4)
      strict_mode.ex              # @moduledoc false - strict-mode validation (§14)
test/
  toon_test.exs                   # Smoke tests for public API
  toon/
    conformance_test.exs          # All spec fixtures (uses @external_resource)
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

> Note: No `lib/toon/types.ex`. Public `@type` declarations live inside `lib/toon.ex`;
> internal types live inside the modules that own them.

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

  test "strict mode returns structured error on length mismatch" do
    assert {:error, %Toon.DecodeError{reason: :length_mismatch}} =
             Toon.decode("tags[3]: a,b", strict: true)
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
git commit -m "chore: init mix project (KirillTemnov/elixir-toon#1)"
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
- [ ] Streaming encode via `encode_lines/2` returns a correct `Enumerable.t()`
- [ ] `decode_from_lines/2` correctly decodes `File.stream!/1` input
- [ ] Atom-keyed maps normalized correctly in encoder
- [ ] Keyword lists preserved in original order during encoding
- [ ] Plain maps encoded with deterministic (sorted-key) output
- [ ] Custom structs encoded via `Toon.Encoder` protocol (with default `Map.from_struct/1`)
- [ ] `decode/2` returns `{:error, %Toon.DecodeError{line: _, reason: _}}` on bad input
- [ ] `encode!/2` and `decode!/2` bang variants work and raise on failure
- [ ] Number canonicalization: trailing zeros stripped, exponent forms accepted on decode
- [ ] All options parameters accept keyword lists (not maps)
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
- **File endings:** All source files (`.ex`, `.exs`, `mix.exs`, `.formatter.exs`, `.gitignore`) must
  end with a trailing newline (`\n`), per project formatting rules

## Follow-up Tasks

1. Submit to `toon-format` organization as official Elixir implementation
2. Consider `Toon.Sigil` (`~TOON`) for compile-time TOON decoding in tests
3. Benchmark vs Jason for LLM prompt construction workflows
4. Add a lazy `decode_stream/2` once a concrete consumer requires per-event streaming
5. Add `NimbleOptions`-based option schema validation for better error messages

> Note: `encode!/2`, `decode!/2`, and the `Toon.Encoder` protocol were moved from
> Follow-up into the v0.1 Solution per Round 1a architecture review.
