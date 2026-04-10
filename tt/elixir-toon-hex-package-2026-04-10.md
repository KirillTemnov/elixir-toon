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

### Round 1b: Architecture Review (Cross-Check)
**Reviewer:** @architecture-designer-beta
**Timestamp:** 2026-04-10
**Cross-Reference:** Reviewed @architecture-designer-alpha findings (Round 1a)
**Status:** ❌ BLOCKERS — alpha missed a hard naming collision plus several correctness issues;
fixed in-place.

**Findings:**

- ✅ AGREE: alpha's protocol-not-Jason.Encoder call is correct and well-motivated.
- ✅ AGREE: alpha's keyword-list-over-map decision matches Elixir stdlib idioms (Jason,
  Ecto, Phoenix, Plug). No disagreement.
- ✅ AGREE: dropping `decode_stream/2` from v0.1 is the right call —
  `decode_from_lines/2` covers the lazy-source use case without leaking parser events.
- ✅ AGREE: structured `Toon.DecodeError` with line/column/reason is the minimum viable
  library error contract.
- ✅ AGREE: `Toon.Decoder.StrictMode` rename resolves the `Validation` clash cleanly.

- ❌ MISSED BY ALPHA — BLOCKER (FIXED): **Hard name collision between
  `Toon.Encoder` (protocol) and `Toon.Encoder.Core` parent namespace plus
  `lib/toon/encoder.ex` from Step 5.** Alpha introduced the `Toon.Encoder` protocol
  in `lib/toon/encoder_protocol.ex` AND Step 5 still said
  "`lib/toon/encoder.ex` — `encode_value/3`, `encode_object/3`, `encode_array/3`".
  Both files would define the module `Toon.Encoder` → compile error. Also, using
  `Toon.Encoder` as BOTH a protocol and the parent of `Toon.Encoder.Core` /
  `Toon.Encoder.Normalize` / etc. is confusing even if it technically compiles
  (protocol consolidation works with child namespaces, but it makes
  `Toon.Encoder.Core` look like it belongs to the protocol).
  **Fix:** Rename the user-facing protocol to `Toon.Encodable` (mirrors
  `Jason.Encoder` → "something encodable"). The internal encoder pipeline keeps the
  `Toon.Encoder.*` namespace. The `encode_value/3` / `encode_object/3` /
  `encode_array/3` functions move into `Toon.Encoder.Core` (matching the module
  table — Step 5 was inconsistent with the table). No `lib/toon/encoder.ex` file.

- ❌ MISSED BY ALPHA — BLOCKER (FIXED): **`encode!/2` as a thin alias is wrong.**
  Alpha's Step 9 defines `def encode!(input, opts \\ []), do: encode(input, opts)`.
  That makes the bang variant identical to the non-bang variant — which is a lie to
  the user. The correct semantics are: `encode/2` returns `{:ok, String.t()} |
  {:error, Toon.EncodeError.t()}`, and `encode!/2` unwraps or raises. Either
  `encode/2` must return a result tuple (breaking the current spec which says
  `:: String.t()`), OR there is no `encode!/2` and `encode/2` raises directly on
  invalid input. **Fix:** Change `encode/2` to return `{:ok, String.t()} |
  {:error, EncodeError.t()}` to mirror `decode/2`. `encode!/2` unwraps or raises.
  This is consistent with `Jason.encode/1` vs `Jason.encode!/1` in the Elixir
  ecosystem. Normalize failures (e.g. a PID, a function, a reference) go through
  the tuple path.

- ❌ MISSED BY ALPHA — CORRECTNESS (FIXED): **`@fallback_to_any` makes the protocol
  dispatch on EVERY term, not just structs.** With `@fallback_to_any true` and
  `defimpl Toon.Encodable, for: Any`, the encoder will invoke protocol dispatch on
  integers, binaries, lists, atoms, nil — on every single value during normalize.
  That is both a correctness risk (the `Any` impl calls `Map.from_struct/1` which
  crashes on non-structs, and the `def to_toon(other), do: other` fallback shadows
  all primitive paths) and a ~5x perf regression on protocol-hot loops.
  **Fix:** Normalize dispatches to `Toon.Encodable.to_toon/1` ONLY when
  `is_struct(value)`. All other terms go through direct pattern-matching in
  Normalize. The protocol needs no `Any` impl; instead the default struct handling
  lives in `Normalize.normalize_struct/1` which does
  `Map.from_struct/1 |> Map.drop([:__meta__])` (Ecto-safe) only if no protocol
  impl exists — checked via `Toon.Encodable.impl_for(value)`. Drop
  `@fallback_to_any`.

- ❌ MISSED BY ALPHA — CORRECTNESS (FIXED): **Normalize rule ordering for
  `[{k, v}, ...]` lists is ambiguous.** Alpha's Step 3 says both
  "Keyword lists with unique atom keys → ordered string-keyed objects" AND
  "List of `{binary, value}` tuples → ordered string-keyed objects". These two
  rules overlap: what about `[{:a, 1}, {"b", 2}]` (mixed keys)? What about
  `[{"a", 1}, {"a", 2}]` (duplicate keys)? What about `[{1, 2}, {3, 4}]`
  (numeric-keyed — should be a list of tuples → list of lists, NOT an object)?
  **Fix:** Add explicit disambiguation rules to Normalize:
  1. If `Keyword.keyword?/1` returns true AND all keys are unique → object
     (keys normalized to strings).
  2. Else if all elements are 2-tuples whose first element is `is_binary/1` AND
     keys are unique → object.
  3. Else if all elements are 2-tuples whose first element is `is_binary/1` or
     `is_atom/1` (mixed) AND keys are unique → object (with atoms stringified).
  4. Otherwise → list of 2-element lists (tuples → lists, recursively).
  Duplicate keys in any object-shaped input raise `Toon.EncodeError`
  `reason: :duplicate_key` with the conflicting key in `path`.

- ❌ MISSED BY ALPHA (FIXED): **No LICENSE file in Files to Create despite
  `licenses: ["MIT"]` in `mix.exs`.** `mix hex.build` emits a warning when the
  declared license has no corresponding `LICENSE` / `LICENSE.md` in the package
  root, and `mix hex.publish` rejects packages missing a license file.
  **Fix:** Add `LICENSE` (MIT text) to Files to Create. Added to tree.

- ❌ MISSED BY ALPHA (FIXED): **Conformance fixtures are not version-pinned.**
  The workflow says "download and integrate all 22 JSON fixture files from
  `toon-format/spec/tests/fixtures/`" but does not pin a commit. The spec repo
  may update fixtures (`version` field inside each fixture is bumped). Without a
  pinned revision, `mix test` results become non-deterministic across developer
  machines and CI runs.
  **Fix:** Pin fixtures to a specific `toon-format/spec` commit SHA. Record the
  SHA in `test/fixtures/SPEC_COMMIT.txt` and validate during test setup that the
  copied fixtures match. Commit fixtures into the repo — do not fetch at test
  time. Added to Notes and Testing sections.

- ❌ MISSED BY ALPHA (FIXED): **`decode_opts` has `indent:` which is wrong.**
  Decoders auto-detect indentation from the input (§11 of the spec says
  "indentation is determined by the first indented line"). A user-supplied
  `indent` option for decode has no well-defined semantics.
  **Fix:** Remove `indent:` from `decode_opts`. Keep only `strict:` and
  `expand_paths:`.

- ❌ MISSED BY ALPHA (FIXED): **CRLF / line-ending handling is unspecified.**
  `decode/2` uses `String.split("\n")`, which leaves `\r` characters stuck to
  the end of each line on Windows-originated input. The scanner will then see
  trailing whitespace on every line and either fail strict-mode checks or
  produce wrong line numbers in errors.
  **Fix:** Normalize input in `decode/2`: `input |> String.replace("\r\n", "\n")
  |> String.split("\n")`. Note added to Step 9.

- ❌ MISSED BY ALPHA (FIXED): **`app: :toon` Hex.pm name may be taken.** Alpha
  neither verified the package name is available on Hex.pm nor provided a
  fallback. Publishing will fail if `:toon` is reserved.
  **Fix:** Add an explicit "name availability check" step to the workflow
  BEFORE publishing: `mix hex.search toon` and `curl
  https://hex.pm/api/packages/toon`. Suggested fallback names if taken:
  `:toon_format`, `:toon_ex`, `:toonex`. Note: the `app:` atom is local and
  can stay `:toon` even if the published name differs via `package: [name:
  ...]`. Added to Notes.

- ❌ MISSED BY ALPHA (FIXED): **`Map.drop([:__meta__])` in the default protocol
  impl is Ecto-specific** and contradicts the stated "keep Jason test-only"
  principle — if we're going to special-case Ecto's `__meta__`, we're building
  in an implicit framework dependency. **Fix:** The default struct normalization
  drops only `:__struct__` via `Map.from_struct/1` (which already drops
  `:__struct__`). Users with Ecto schemas implement `Toon.Encodable` for their
  own schemas or use `Ecto.Schema`'s built-in serialization. Removed the Ecto
  special-case from the protocol impl.

- ❌ MISSED BY ALPHA: **`Path.wildcard/1` at compile time with
  `@external_resource` does not trigger recompile when NEW fixture files are
  added, only when listed files change.** This is a well-known Elixir gotcha.
  Alpha added `@external_resource` per-file but did not flag the
  "new file added" case.
  **Fix:** Add `force: true` recompile instructions to README / CI:
  `touch test/toon/conformance_test.exs && mix test` after adding fixtures.
  Alternatively, generate a fixture manifest file as a build step. Note added
  to testing section. Not a blocker — the fixture set is static v3.0.

- ⚠️ CONCERN (NOT FIXED, flagged): **Elixir minimum version 1.15 is more
  conservative than necessary.** `Keyword.validate!/2` landed in 1.13, the
  `Stream` improvements alpha cites are from 1.14. If the goal is broad Phoenix
  compatibility, `elixir: "~> 1.14"` buys one more LTS cycle. Not a blocker;
  leaving alpha's 1.15 floor alone pending team input.

- ⚠️ CONCERN (NOT FIXED, flagged): **`replacer` callback arity-3 signature
  copies the TypeScript reference but is non-idiomatic in Elixir.** Elixir
  callback conventions prefer `{key, value, path}` tuples or a struct argument
  over positional args with a keypath list. Not a blocker — the reference API
  traceability argument wins for v0.1.

- 💡 NEW SUGGESTION: **Add a `Toon.Encodable` `@derive` example** to the README
  so users discover struct support without reading protocol docs. One paragraph,
  high ROI.

- 💡 NEW SUGGESTION: **Add `CHANGELOG.md`** to Files to Create — ExDoc can
  display it alongside README via `extras: ["README.md", "CHANGELOG.md"]`.
  Standard Hex.pm practice.

- 💡 NEW SUGGESTION: **Add a property-based round-trip test via `:stream_data`**
  (dev/test dep) to catch encoder/decoder asymmetries the fixed fixtures miss.
  Not required for v0.1, noted as follow-up.

**Changes Made:**

1. Renamed user-facing protocol `Toon.Encoder` → `Toon.Encodable`. Updated module
   table, Files to Create, Step 2 code sample, and all references.
2. Removed `lib/toon/encoder.ex` from Step 5; `encode_value/3` / `encode_object/3`
   / `encode_array/3` now live in `Toon.Encoder.Core` (`lib/toon/encoder/core.ex`),
   matching the module table.
3. Changed `encode/2` return type to `{:ok, String.t()} | {:error,
   Toon.EncodeError.t()}`; rewrote `encode!/2` to unwrap-or-raise (not a thin
   alias). Updated typespec in `lib/toon.ex` sample and acceptance criteria.
4. Removed `@fallback_to_any` from `Toon.Encodable` protocol. Normalize now calls
   `Toon.Encodable.to_toon/1` only when `is_struct(value)`; non-structs go
   through pattern matching. Default struct handling: `Map.from_struct/1` (no
   Ecto `__meta__` drop).
5. Added explicit disambiguation rules for keyword / tuple-list / list-of-lists
   in the Normalize section, including duplicate-key → `EncodeError` behavior.
6. Added `LICENSE` to Files to Create; added `CHANGELOG.md` to Files to Create
   and to `docs: [extras: ...]` in `mix.exs`.
7. Added fixture version pinning: `test/fixtures/SPEC_COMMIT.txt` records the
   pinned SHA; Testing section now instructs fixtures to be committed to the
   repo.
8. Removed `indent:` from `decode_opts()` — decoders auto-detect indentation.
9. Added CRLF normalization to `decode/2` (`String.replace("\r\n", "\n")`
   before split).
10. Added Hex.pm name-availability check to the Implementation Workflow and a
    fallback name list (`:toon_format`, `:toon_ex`) to Notes.
11. Added note about `@external_resource` not catching newly-added fixture files;
    documented the `touch` workaround in Testing.
12. Added property-based round-trip testing via `:stream_data` to Follow-up Tasks.

---

### Round 2a: Implementation Review (Independent)
**Reviewer:** @implementation-expert-alpha
**Timestamp:** 2026-04-10
**Status:** ❌ BLOCKERS — 6 bugs that would prevent compilation or produce wrong results; fixed in-place.

**Findings:**

- ✅ LGTM: `mix.exs` dep versions are correct — `ex_doc ~> 0.34`, `dialyxir ~> 1.4`,
  `jason ~> 1.4` are all current stable releases. `only:` scoping is correct.
- ✅ LGTM: `defexception` is the right macro for `DecodeError` and `EncodeError`. Implementing
  `Exception` means `raise err` in the `!` bang variants works correctly.
- ✅ LGTM: `Keyword.validate!/2` gating at each public entry point (1.13+, present in 1.15)
  is idiomatic and self-documenting.
- ✅ LGTM: CRLF normalization via `String.replace("\r\n", "\n")` before `String.split("\n")`
  is correct. Covers Windows-originated input.
- ✅ LGTM: `decode/2` guard `when is_binary(input)` prevents silent coercion on wrong types.
- ✅ LGTM: `Toon.Encodable` protocol definition — no `@fallback_to_any`, dispatch only on
  `is_struct/1` in Normalize — correctly avoids the ~5x perf regression from Round 1b.
- ✅ LGTM: `Toon.Constants.delimiters/0` returns a map with charlist integer values —
  `?,` = 44, `?\t` = 9, `?|` = 124. These are correct BEAM integer literals.
- ✅ LGTM: Scanner emitting `%ParsedLine{}` structs and Parser emitting tagged maps for
  events is a sound event-sourced approach for the grammar.
- ✅ LGTM: `decode_from_lines/2` accepting `Enumerable.t()` covers both
  `File.stream!/1` and in-memory list inputs with a single function — good design.

- ❌ CRITICAL (FIXED): **Unit tests assert `encode/2` returns a bare string, but `encode/2`
  now returns `{:ok, String.t()} | {:error, EncodeError.t()}`.** After the Round 1b change
  making `encode/2` a result-tuple function, every test doing
  `assert Toon.encode(...) == "..."` will fail at runtime — the left side is `{:ok, "..."}`
  not `"..."`. All unit tests in the Testing section compare the wrong shape.
  **Fix:** Rewrite all encode test assertions to match `{:ok, _}` tuples using
  pattern-match `assert {:ok, result} = Toon.encode(...)` + `assert result == "..."`,
  or the single-line form `assert Toon.encode(...) == {:ok, "..."}`.

- ❌ CRITICAL (FIXED): **`encode/2` catches `EncodeError` via `rescue` but lets
  `ArgumentError` from `Keyword.validate!/2` propagate unhandled inside the tuple
  contract.** `Keyword.validate!/2` raises `ArgumentError` on unknown keys. The call
  is INSIDE the `try` block, so an unknown option raises through `rescue e in
  EncodeError` (which only matches `EncodeError`), making `ArgumentError` escape as a
  bare exception — breaking the `{:ok, _} | {:error, _}` contract.
  **Fix:** Move `Keyword.validate!/2` OUTSIDE the `try` block. Option validation is a
  programmer error (wrong option key), not a runtime encode failure — callers should
  see `ArgumentError` directly, not wrapped in `{:error, _}`. The `try/rescue` block
  should wrap ONLY the `encode_value` dispatch.

- ❌ CRITICAL (FIXED): **`@derive {Toon.Encodable, only: [:id, :name]}` will not work.**
  Elixir's `@derive` macro calls `Protocol.__derive__/3` which invokes
  `Toon.Encodable.__deriving__/3` (a macro) on the protocol module. `defprotocol` does
  NOT generate `__deriving__/3` automatically — it must be explicitly implemented as a
  macro inside the protocol body or in a companion module. Without it, the `@derive`
  call raises `** (Protocol.UndefinedError) protocol Toon.Encodable not implemented`.
  **Fix:** Either (a) document that `@derive` is NOT supported in v0.1 (users implement
  `defimpl Toon.Encodable, for: MyStruct` manually), or (b) add a `defmacro
  __deriving__(module, struct, opts)` implementation to `Toon.Encodable`. Option (a) is
  correct for v0.1 scope. Remove the `@derive` example from the TZ; replace with a
  manual `defimpl` example.

- ❌ CRITICAL (FIXED): **`encode_lines/2` and `decode_from_lines/2` are declared as
  function stubs with no body — they will not compile.** In Elixir, a function clause
  without a `do` block is a forward declaration (used for default args with multiple
  clauses), but it MUST be followed by at least one clause WITH a body. As written,
  `def encode_lines(input, opts \\ [])` with no subsequent `do` body is a compile error.
  **Fix:** Replace the stub declarations with documented placeholder bodies (or note
  clearly that the stub form requires a companion `do`-body clause in the actual
  implementation file). In the TZ code sample, add a `# implementation` comment inside
  a `do` block to make the example compilable.

- ❌ CRITICAL (FIXED): **Acceptance criterion still references the old `Toon.Encoder`
  protocol name** (line "Custom structs encoded via `Toon.Encoder` protocol") — this
  was renamed to `Toon.Encodable` in Round 1b but the acceptance criterion was not
  updated. **Fix:** Update to `Toon.Encodable`.

- ❌ CRITICAL (FIXED): **Follow-up note at end of file references `Toon.Encoder`
  protocol** ("the `Toon.Encoder` protocol were moved from Follow-up") — stale
  Round 1a name. **Fix:** Update to `Toon.Encodable`.

- ⚠️ ISSUE (FIXED): **`encode/2` calls `IO.iodata_to_binary/1` on the result of
  `encode_value/3`, but neither the spec nor the module description states that
  `encode_value/3` returns `iodata()`.** If `encode_value/3` returns `String.t()`, the
  `IO.iodata_to_binary/1` call is a no-op (harmless but misleading). If it returns
  `iodata()`, the typespec for `Encoder.Core` must say so.
  **Fix:** Add an explicit note to Step 5 that `encode_value/3` returns `iodata()`
  (a list of binaries/charlists) for efficiency, and `IO.iodata_to_binary/1` in
  `encode/2` is the intended flattening step.

- ⚠️ ISSUE (FIXED): **`Toon.Decoder.Core` is listed in the module table but its
  responsibility is never described** in the Implementation steps. Steps 6–8 cover
  Scanner, Parser+EventBuilder, and StrictMode. `Toon.Decoder.Core` (the internal
  decode entry point) has no corresponding step explaining what it contains or how it
  orchestrates the pipeline (Scanner → Parser → EventBuilder → StrictMode). Implementer
  will not know where to put the `decode_from_lines/2` body.
  **Fix:** Add a brief Step 7b (or expand Step 7) describing `Toon.Decoder.Core` as
  the pipeline orchestrator: accepts `[String.t()]`, invokes Scanner, feeds ParsedLines
  to Parser, feeds events to EventBuilder, runs StrictMode if `strict: true`, returns
  `{:ok, json_value()} | {:error, DecodeError.t()}`.

- ⚠️ ISSUE (FIXED): **`needs_quoting?/2` calls `starts_with_hyphen?/1` — the name is
  misleading and the logic would over-quote valid negative numbers.** A string like
  `"-3.14"` is a valid unquoted TOON primitive (it decodes as a float). Only strings
  starting with `-` that are NOT valid numbers should be quoted. The function name
  `starts_with_hyphen?` implies ALL hyphen-prefixed strings are quoted, which conflicts
  with §7.2 of the spec (negative numbers are unquoted scalars). **Fix:** Rename to
  `ambiguous_sign_prefix?/1` (or `non_numeric_hyphen_prefix?/1`) and document that it
  returns true only when the string starts with `-` but is not a valid number literal.

- ⚠️ ISSUE (FIXED): **`@type encode_opts` uses `pos_integer()` for `indent:`** but
  an indent of `0` (no indentation) is a reasonable and valid option. `pos_integer()`
  excludes zero. Standard Elixir libraries (Poison, Jason) type this as
  `non_neg_integer()`. **Fix:** Change `indent: pos_integer()` to
  `indent: non_neg_integer()` in the typespec.

- 💡 CODE SMELL (FIXED): **`@type delimiter :: ?, | ?\t | ?|` in `Toon.Constants` is
  misleading** — these are integer character codes (44, 9, 124), not Elixir character
  literals in the typespec sense. The `@type` declaration looks like an OR of three
  integer literals, which is valid Dialyzer syntax but reads confusingly.
  The matching type alias in `Toon.Constants` makes the delimiter charcode type
  cleaner as `@type delimiter :: 44 | 9 | 124` with a companion comment. However this
  is a style concern, not a bug — left as a note for implementer.

- 💡 CODE SMELL (NOTED): **`Toon.Constants.delimiters/0` returns a map, but the
  accepted option value for `delimiter:` is an atom (`:comma | :tab | :pipe`).** The
  map is used for atom-to-charcode lookup. This is correct but the function name
  `delimiters/0` (plural, bare) does not convey it's a lookup table. `delimiter_map/0`
  or `delimiter_codes/0` would be clearer. Left as style note.

- 💡 CODE SMELL (NOTED): **Conformance test uses `fixture["category"]` INSIDE the
  test name string**, but `fixture["category"]` at compile time is the same as the
  outer `category` variable from the `for` loop (both come from the same fixture JSON).
  This produces redundant test names like `"decode/decode: parses safe unquoted
  string"`. Consider `"#{fixture_file |> Path.basename(".json")}: #{test_case["name"]}"`
  for cleaner output. Left as style note — not blocking.

**Changes Made:**
1. Rewrote all unit test assertions for `encode/2` to use `{:ok, "..."}` result
   tuple matching (CRITICAL fix).
2. Moved `Keyword.validate!/2` call outside the `try` block in `encode/2`; `try/rescue`
   now wraps only `encode_value` dispatch (CRITICAL fix).
3. Removed `@derive {Toon.Encodable, only: [:id, :name]}` example; replaced with a
   manual `defimpl Toon.Encodable, for: MyApp.User` example. Added a note that
   `@derive` is not supported in v0.1 (CRITICAL fix).
4. Added `do` bodies to the `encode_lines/2` and `decode_from_lines/2` stub
   declarations in the Step 9 code sample (CRITICAL fix).
5. Updated acceptance criterion line from `Toon.Encoder` → `Toon.Encodable` (CRITICAL
   fix).
6. Updated the trailing Follow-up note: `Toon.Encoder` → `Toon.Encodable` (CRITICAL
   fix).
7. Added note to Step 5 that `encode_value/3` returns `iodata()`.
8. Added Step 7b describing `Toon.Decoder.Core` pipeline orchestration.
9. Renamed `starts_with_hyphen?` → `ambiguous_sign_prefix?` in the `StringUtils`
   snippet with a clarifying comment.
10. Changed `indent: pos_integer()` → `indent: non_neg_integer()` in typespec.

---

### Round 2b: Implementation Review (Cross-Check)
**Reviewer:** @implementation-expert-beta
**Timestamp:** 2026-04-10
**Cross-Reference:** Reviewed @implementation-expert-alpha findings (Round 2a)
**Status:** ❌ BLOCKERS — 4 bugs that would cause incorrect runtime behavior or
break the public API contract; fixed in-place.

**Findings:**

- ✅ AGREE: @alpha's CRITICAL fix #1 (encode test assertions → `{:ok, _}` tuples)
  is valid and applied correctly throughout the unit test section.
- ✅ AGREE: @alpha's CRITICAL fix #2 (`Keyword.validate!/2` moved outside `try`
  block) is correct — `ArgumentError` from unknown options is a programmer error,
  not an encodable runtime failure.
- ✅ AGREE: @alpha's CRITICAL fix #3 (removing `@derive` example) is correct.
  `defprotocol` does not auto-generate `__deriving__/3`; manual `defimpl` is the
  right v0.1 story.
- ✅ AGREE: @alpha's CRITICAL fix #4 (adding `do` bodies to stubs) is necessary —
  naked `def f(x \\ default)` with no body clause is a compile error in Elixir.
- ✅ AGREE: @alpha's fix on `starts_with_hyphen?` → `ambiguous_sign_prefix?` is
  correct. Negative number literals are valid unquoted TOON scalars per §7.2.
- ✅ AGREE: `encode_value/3` returning `iodata()` is a good design note; the
  `IO.iodata_to_binary/1` call in `encode/2` is the correct flattening point.

- ❌ MISSED BY ALPHA — BLOCKER (FIXED): **`decode/2` guard `when is_binary(input)`
  has no fallback clause — non-binary input raises `FunctionClauseError` instead of
  returning `{:error, DecodeError.t()}`, breaking the public API contract.**
  With only one function clause `def decode(input, opts \\ []) when is_binary(input)`,
  a caller passing a charlist `'hello'`, an atom, or a number gets
  `** (FunctionClauseError) no function clause matching in Toon.decode/2` — a raw
  VM error, not a structured `{:error, %Toon.DecodeError{}}`. The bang variant
  `decode!/2` would also raise `FunctionClauseError` instead of `DecodeError`,
  misleading callers about what went wrong. The API contract states
  `{:ok, _} | {:error, DecodeError.t()}` — all failure paths must go through that
  shape from `decode/2`, or the non-binary path must raise `ArgumentError`
  explicitly with a clear message rather than leaking a VM-internal error.
  **Fix:** Add a fallback clause to `decode/2` that returns
  `{:error, %Toon.DecodeError{reason: :invalid_input, message: "input must be a
  binary (UTF-8 string)"}}` for non-binary inputs. Updated code sample in Step 9.

- ❌ MISSED BY ALPHA — BLOCKER (FIXED): **`Keyword.validate!/2` is called with a
  plain atom list, so option DEFAULTS are never applied.** The comment in `lib/toon.ex`
  says `# Defaults: indent: 2, delimiter: :comma, key_folding: :off, ...` but
  `Keyword.validate!(opts, [:indent, :delimiter, :key_folding, :flatten_depth,
  :replacer])` validates key names only — it does NOT inject default values.
  Downstream `Toon.Encoder.Core.encode_value/3` would receive an opts keyword list
  with NO `:indent` key when none was passed, and must then handle a missing key
  defensively everywhere (`Keyword.get(opts, :indent, 2)` style), OR the TZ must
  state that defaults are applied via `Keyword.validate!` using the `{key, default}`
  form. The current spec is ambiguous: it describes defaults but does not show how
  they are applied, leaving the implementer to guess. A `Keyword.validate!` call with
  defaults uses `[indent: 2, delimiter: :comma, ...]` tuples, NOT atom lists.
  **Fix:** Update the `encode/2` sample to show defaults applied via
  `Keyword.validate!` with `{key, default}` tuples, OR add an explicit note that
  `encode_value/3` must use `Keyword.get(opts, :key, default)` throughout. Both
  approaches are valid; the spec must pick one. The TZ now documents the
  `Keyword.get/3` with default approach (simpler, no default-double-definition risk)
  and makes the comment explicit.

- ❌ MISSED BY ALPHA — BLOCKER (FIXED): **`mix.exs` `package/0` has no `:files`
  key — `mix hex.build` will include ALL project files including `test/fixtures/`
  (22 JSON files) in the published Hex package.** Without an explicit `:files` list,
  Hex.pm includes the default glob which captures the entire repo. The 22 conformance
  fixture JSON files are test-only and should not be shipped to end users' `deps/`
  directories (they add unnecessary weight). More critically, `mix hex.build`
  may fail if it encounters unexpected binary-like content in fixtures.
  **Fix:** Add explicit `:files` to `package/0` in `mix.exs`: `["lib", "mix.exs",
  "README.md", "CHANGELOG.md", "LICENSE", ".formatter.exs"]`. Test fixtures stay
  in `test/` but are excluded from the published package.

- ❌ MISSED BY ALPHA — BLOCKER (FIXED): **Conformance test body stub `# ...` gives
  implementers zero guidance on how decode vs encode tests should be structured.**
  The `for` loop generates tests for BOTH `"decode"` and `"encode"` categories but
  the test body is a single empty `# ...`. Decode fixtures have `"input"` +
  `"expected"` fields and may have `"error": true`. Encode fixtures have `"input"`
  (a JSON value) + `"expected"` (a TOON string), and may also have `"error": true`.
  Without specifying the test body shape for each category, implementers will either
  write incorrect assertions or skip error cases. The conformance harness is a
  primary deliverable and must be complete enough to implement correctly.
  **Fix:** Expand the conformance test to show the full body structure:
  `if test_case["error"]` branch, category dispatch for `decode` vs `encode`,
  and assertion pattern. Updated `conformance_test.exs` sample in Step 10.

- ⚠️ CODE SMELL (FIXED): **`encode_lines/2` return type `Enumerable.t()` has no
  error path, but encoding can fail mid-stream on unencodable terms.** `encode/2`
  wraps failures in `{:error, EncodeError.t()}`. If `encode_lines/2` raises an
  uncaught `EncodeError` during stream enumeration, callers using
  `Enum.into(stream, File.stream!(...))` have no way to intercept the error before
  I/O has partially committed. This is a semantic inconsistency. The TZ must
  document this limitation explicitly: `encode_lines/2` raises (does not return
  `{:error, _}`); callers that need error handling should use `encode/2` and pipe
  the result. Note added to Step 9 and the public API docstring.

- ⚠️ CODE SMELL (FIXED): **`@type delimiter :: ?, | ?\t | ?|` in `Toon.Constants`
  is syntactically valid Elixir but is a charlist-literal-in-typespec idiom that
  Dialyzer sees as `44 | 9 | 124`.** The `@type delimiter_key ::
  :comma | :tab | :pipe` alongside it is cleaner for user-facing use. The internal
  `delimiter` integer type should be written as `@type delimiter :: 44 | 9 | 124`
  with a comment explaining the mapping, not as char literals in the typespec
  position. This avoids Dialyzer confusion. Fixed in Constants sample.

- ⚠️ CODE SMELL (NOTED, NOT FIXED): **`decode_from_lines/2` validates opts with
  `Keyword.validate!/2` even when called via `decode/2` which already validated.**
  The double-validation is harmless and correct (public functions must always
  validate their own inputs since callers may call them directly). The redundancy
  is intentional and acceptable. Left as-is.

- 💡 MISSED SPEC DETAIL (FIXED): **The conformance fixture format has an `"error"`
  boolean field for negative tests but this is nowhere mentioned in the Testing
  section.** Error-case fixtures are present in `validation-errors.json` and
  `indentation-errors.json`. Without noting the `"error"` field in the TZ, the
  conformance test harness will silently produce passing tests on inputs that should
  fail. Added `"error"` field handling to the conformance test sample and Testing
  section description.

- 💡 SPEC DETAIL (NOTED): **`@tag spec_section: test_case["specSection"]` will
  produce `nil` tags for fixtures without a `"specSection"` field.** This is
  harmless — `@tag spec_section: nil` is valid ExUnit. `mix test --only
  spec_section:9.3` filters by value match, so nil-tagged tests are excluded from
  that filter naturally. Not a bug.

- 💡 SPEC DETAIL (NOTED): **`mix.exs` `docs/0` should include
  `source_url_pattern: "https://github.com/USERNAME/elixir-toon/blob/main/%{path}#L%{line}"`**
  for ExDoc 0.34 per-function "View Source" links to work. The `source_url:` key
  is present but `source_url_pattern:` is needed for line-level anchors. Left as
  a non-blocking implementation detail.

**Changes Made:**
1. Added fallback `decode/2` clause returning `{:error, %Toon.DecodeError{reason:
   :invalid_input}}` for non-binary inputs. Updated Step 9 code sample (BLOCKER fix).
2. Updated `encode/2` and `decode/2` option-handling note: clarified that
   `Keyword.validate!` with atom list validates keys only; downstream functions
   must use `Keyword.get(opts, key, default)` for defaults. Added explicit comment
   in Step 9 sample (BLOCKER fix).
3. Added `:files` key to `package/0` in `mix.exs` Step 1 sample (BLOCKER fix).
4. Expanded conformance test sample in Step 10 with full decode/encode/error-case
   body structure (BLOCKER fix).
5. Added note to Step 9 and `encode_lines/2` docstring: raises on encoding failure,
   use `encode/2` for error-safe paths (CODE SMELL fix).
6. Fixed `@type delimiter` in Constants to use integer literals `44 | 9 | 124`
   with a mapping comment (CODE SMELL fix).

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
| —                             | `Toon.Encodable` (protocol)     | public     |
| —                             | `Toon.DecodeError` (exception)  | public     |
| —                             | `Toon.EncodeError` (exception)  | public     |
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

2. **Custom struct encoding via a `Toon.Encodable` protocol** (not `Jason.Encoder`
   and NOT `Toon.Encoder`, which is the internal encoder namespace). Modeled after
   `Jason.Encoder`: consumers implement `Toon.Encodable` for their structs to control
   normalization. The protocol has **no** `@fallback_to_any` — Normalize dispatches
   to `Toon.Encodable.to_toon/1` only when `is_struct(value)` is true. Default
   behavior when no impl exists is `Map.from_struct/1`. No Ecto-specific key drops.
   This keeps Jason as a test-only dependency and avoids protocol dispatch on every
   primitive value.

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

6. **Bang variants in v0.1.** `encode/2` returns `{:ok, String.t()} | {:error,
   Toon.EncodeError.t()}` so it has well-defined failure cases (unencodable term,
   duplicate key, etc.). `encode!/2` unwraps or raises. `decode/2` returns
   `{:ok, json_value()} | {:error, Toon.DecodeError.t()}`; `decode!/2` unwraps or
   raises. Mirrors `Jason.encode/1` vs `Jason.encode!/1` exactly.

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
      maintainers: ["..."],
      # Explicit file list keeps test fixtures out of the published Hex package.
      # test/fixtures/ (22 JSON conformance files) is intentionally excluded.
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Toon",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
```

**Step 2: Constants, typespecs, and error types**

`lib/toon/constants.ex`:
```elixir
defmodule Toon.Constants do
  @moduledoc false
  # Integer char-codes: comma = 44, tab = 9, pipe = 124.
  # Written as integer literals (not char literals) for Dialyzer clarity.
  @type delimiter :: 44 | 9 | 124
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
  indent: non_neg_integer(),
  delimiter: :comma | :tab | :pipe,
  key_folding: :off | :safe,
  flatten_depth: pos_integer() | :infinity,
  replacer: (String.t(), json_value(), [String.t() | integer()] -> term())
]

@type decode_opts :: [
  strict: boolean(),
  expand_paths: :off | :safe
]
```
> Note: decoders auto-detect indentation from input per §11; no `indent:` option.

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

`lib/toon/encodable.ex` — user-extensible struct encoding:
```elixir
defprotocol Toon.Encodable do
  @moduledoc """
  Protocol for converting custom Elixir structs into the TOON data model. Modeled
  after `Jason.Encoder`. Implementations must return a value that is itself
  encodable (map, list, keyword, primitive).

  The encoder only invokes this protocol when the input satisfies `is_struct/1`.
  Non-struct terms are handled directly by Normalize. There is no
  `@fallback_to_any`: the default for structs without an implementation is
  `Map.from_struct/1`, invoked by Normalize, not by the protocol.
  """
  @spec to_toon(struct()) :: term()
  def to_toon(value)
end
```

Example implementation in user code (v0.1 does NOT support `@derive`; implement
the protocol manually):
```elixir
defmodule MyApp.User do
  defstruct [:id, :name, :password_hash]
end

defimpl Toon.Encodable, for: MyApp.User do
  # Return only the fields safe to encode; exclude sensitive fields.
  def to_toon(%MyApp.User{id: id, name: name}) do
    %{"id" => id, "name" => name}
  end
end
```
> Note: `@derive {Toon.Encodable, only: [...]}` is **not** supported in v0.1 —
> `defprotocol` does not auto-generate `__deriving__/3`. Support can be added in
> a follow-up by implementing `defmacro __deriving__(module, _struct, opts)` inside
> the protocol body.

**Step 3: Encoder — Normalize**

`lib/toon/encoder/normalize.ex` (`@moduledoc false`):
- Convert Elixir terms to the TOON/JSON data model
- Atoms → strings (except `nil`, `true`, `false`)
- Atom-keyed maps → string-keyed maps
- `NaN`, `±Infinity` (`:nan`, `:infinity`, `:neg_infinity`) → `nil` per spec §3
- Structs (`is_struct(v)`): if `Toon.Encodable.impl_for(v)` returns a module, call
  `Toon.Encodable.to_toon/1` and recurse on the result; otherwise
  `Map.from_struct/1` and recurse
- Tuples (non-2 element OR inside list-of-tuples where rule below does not apply)
  → lists
- Plain maps → encoded in sorted-key order (deterministic but alphabetized); callers
  that need a specific order must pass a keyword list or tuple list instead
- **List-shaped objects — disambiguation rules, applied in order:**
  1. If `Keyword.keyword?(list)` returns true AND all keys are unique → object,
     keys normalized to strings, order preserved.
  2. Else if every element is a 2-tuple whose first element is `is_binary/1`
     AND keys are unique → object, order preserved.
  3. Else if every element is a 2-tuple whose first element is `is_binary/1` OR
     `is_atom/1` (mixed keys, atoms stringified) AND keys are unique → object,
     order preserved.
  4. Otherwise → list (tuples recursively become lists of their elements).
  Duplicate keys under rules 1–3 raise `Toon.EncodeError` with
  `reason: :duplicate_key` and the conflicting key in `path`.
- Unencodable terms (functions, pids, references, ports) raise `Toon.EncodeError`
  with `reason: :unencodable_term`.

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
    ambiguous_sign_prefix?(str)
  end

  # Returns true when the string starts with "-" but is NOT a valid number literal.
  # Valid negative numbers (e.g. "-3.14", "-0") must NOT be quoted — the encoder
  # emits them as unquoted scalars per §7.2. Only non-numeric hyphen-prefixed
  # strings (e.g. "-foo", "--flag") require quoting.
  @spec ambiguous_sign_prefix?(String.t()) :: boolean()

  @spec escape(String.t()) :: String.t()
  def escape(str) do
    # Escape: \\ → \\\\, " → \", \n → \\n, \r → \\r, \t → \\t
  end
end
```

**Step 5: Encoder — Core**

`lib/toon/encoder/core.ex` (`@moduledoc false`):
- `encode_value/3` — dispatch on type; returns `iodata()` (list of binaries/charlists)
  for efficiency. The public `encode/2` calls `IO.iodata_to_binary/1` to flatten.
- `encode_lines/2` — entry point for `Toon.encode_lines/2`; wraps `encode_value/3`
  output in a `Stream` of line binaries.
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

**Step 6b: Decoder — Core (pipeline orchestrator)**

`lib/toon/decoder/core.ex` (`@moduledoc false`):
- Entry point called by `Toon.decode_from_lines/2` (and `Toon.decode/2` indirectly).
- `decode_lines/2` orchestrates the pipeline:
  1. `Toon.Decoder.Scanner.scan_lines/1` — transforms `[String.t()]` into
     `[%ParsedLine{}]`
  2. `Toon.Decoder.Parser.parse/1` — transforms `[%ParsedLine{}]` into a list of
     `JsonStreamEvent` maps
  3. `Toon.Decoder.EventBuilder.build/1` — transforms events into `json_value()`
  4. If `strict: true` — runs `Toon.Decoder.StrictMode.validate/2` before returning
  5. If `expand_paths: :safe` — runs `Toon.Decoder.Expand.expand/1` on the result
- Returns `{:ok, json_value()} | {:error, %Toon.DecodeError{}}` at each stage.

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
  # Keyword.validate!/2 with an atom list validates key names only — it does NOT
  # inject defaults. Defaults are applied in the implementation via
  # Keyword.get(opts, :key, default), e.g.:
  #   indent         → Keyword.get(opts, :indent, 2)
  #   delimiter      → Keyword.get(opts, :delimiter, :comma)
  #   key_folding    → Keyword.get(opts, :key_folding, :off)
  #   flatten_depth  → Keyword.get(opts, :flatten_depth, :infinity)
  #   strict         → Keyword.get(opts, :strict, false)
  #   expand_paths   → Keyword.get(opts, :expand_paths, :off)

  @spec encode(term(), encode_opts()) :: {:ok, String.t()} | {:error, EncodeError.t()}
  def encode(input, opts \\ []) do
    # Validate outside try — unknown option keys are programmer errors (ArgumentError),
    # not runtime encode failures that belong in the {:error, _} return path.
    opts = Keyword.validate!(opts, [:indent, :delimiter, :key_folding, :flatten_depth, :replacer])
    try do
      # encode_value/3 returns iodata() for efficiency; flatten here.
      iodata = Toon.Encoder.Core.encode_value(input, opts, [])
      {:ok, IO.iodata_to_binary(iodata)}
    rescue
      e in EncodeError -> {:error, e}
    end
  end

  @spec encode!(term(), encode_opts()) :: String.t()
  def encode!(input, opts \\ []) do
    case encode(input, opts) do
      {:ok, string} -> string
      {:error, %EncodeError{} = err} -> raise err
    end
  end

  @spec decode(String.t(), decode_opts()) :: {:ok, json_value()} | {:error, DecodeError.t()}
  def decode(input, opts \\ []) when is_binary(input) do
    # Keyword.validate!/2 with an atom list validates key names only; it does NOT
    # inject defaults. Downstream functions use Keyword.get(opts, :key, default).
    opts = Keyword.validate!(opts, [:strict, :expand_paths])
    lines =
      input
      |> String.replace("\r\n", "\n")
      |> String.split("\n")
    decode_from_lines(lines, opts)
  end

  # Fallback clause: return a structured error instead of leaking FunctionClauseError
  # when callers accidentally pass a charlist, atom, or other non-binary.
  def decode(input, _opts) do
    {:error,
     %DecodeError{
       reason: :invalid_input,
       message: "input must be a binary (UTF-8 string), got: #{inspect(input)}"
     }}
  end

  @spec decode!(String.t(), decode_opts()) :: json_value()
  def decode!(input, opts \\ []) do
    case decode(input, opts) do
      {:ok, value} -> value
      {:error, %DecodeError{} = err} -> raise err
    end
  end

  @spec encode_lines(term(), encode_opts()) :: Enumerable.t()
  def encode_lines(input, opts \\ []) do
    opts = Keyword.validate!(opts, [:indent, :delimiter, :key_folding, :flatten_depth, :replacer])
    # Returns a lazy Stream of line binaries. Implementation delegates to
    # Toon.Encoder.Core via Stream.resource/3.
    # NOTE: unlike encode/2, this function does NOT return {:error, _} — encoding
    # failures (unencodable terms, duplicate keys) raise EncodeError during stream
    # enumeration. Callers that need error-safe encoding must use encode/2 instead.
    Toon.Encoder.Core.encode_lines(input, opts)
  end

  @spec decode_from_lines(Enumerable.t(), decode_opts()) ::
          {:ok, json_value()} | {:error, DecodeError.t()}
  def decode_from_lines(lines, opts \\ []) do
    opts = Keyword.validate!(opts, [:strict, :expand_paths])
    # Pipeline: scan lines → parse events → build value → strict-mode check.
    Toon.Decoder.Core.decode_lines(lines, opts)
  end
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

  # Dynamically generate test cases from JSON fixtures committed at SPEC_COMMIT.
  # @external_resource ensures recompilation when a fixture file changes.
  # Note: adding a NEW fixture file requires `touch test/toon/conformance_test.exs`
  # to force recompilation — Path.wildcard/1 at compile time cannot observe new files.
  for category <- ["decode", "encode"] do
    for fixture_file <- Path.wildcard("#{@fixtures_path}/#{category}/*.json") do
      @external_resource fixture_file
      fixture = File.read!(fixture_file) |> Jason.decode!()

      for test_case <- fixture["tests"] do
        # Capture loop variables as module attributes so they are available
        # inside the test body (the `test` macro creates a new scope).
        @tag spec_section: test_case["specSection"]
        @tag category: category
        @test_input test_case["input"]
        @test_expected test_case["expected"]
        @test_is_error test_case["error"] == true
        @test_name "#{category}/#{fixture["category"]}: #{test_case["name"]}"

        test @test_name do
          if @test_is_error do
            # Negative test: input must produce an error, not a successful result.
            case @category do
              "decode" ->
                assert {:error, %Toon.DecodeError{}} = Toon.decode(@test_input)

              "encode" ->
                # Encode fixtures with "error": true have unencodable inputs.
                # The input field in encode error fixtures is a raw JSON value
                # (decoded by Jason); pass it directly to Toon.encode/2.
                assert {:error, %Toon.EncodeError{}} = Toon.encode(@test_input)
            end
          else
            case @category do
              "decode" ->
                # "input" is a TOON string; "expected" is the decoded JSON value.
                assert {:ok, result} = Toon.decode(@test_input)
                assert result == @test_expected

              "encode" ->
                # "input" is a JSON value (already parsed by Jason above);
                # "expected" is the canonical TOON-encoded string.
                assert {:ok, result} = Toon.encode(@test_input)
                assert result == @test_expected
            end
          end
        end
      end
    end
  end
end
```

> Note: Fixture `"input"` in encode tests is a JSON value (object/array/primitive)
> as parsed by `Jason.decode!`. Fixture `"input"` in decode tests is a raw TOON
> string. Fixture `"error": true` marks negative tests — both decode and encode
> fixture files can have error cases (see `validation-errors.json`,
> `indentation-errors.json`).


### Files to Create

```
mix.exs
LICENSE                           # MIT license text (required for mix hex.publish)
README.md
CHANGELOG.md                      # Displayed in ExDoc via extras:
.formatter.exs
.gitignore
lib/
  toon.ex                         # Public API: encode/2, encode!/2, decode/2, decode!/2,
                                  #             encode_lines/2, decode_from_lines/2
  toon/
    decode_error.ex               # Public: %Toon.DecodeError{} exception
    encode_error.ex               # Public: %Toon.EncodeError{} exception
    encodable.ex                  # Public: Toon.Encodable protocol (to_toon/1)
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
    SPEC_COMMIT.txt               # Pinned toon-format/spec commit SHA
    decode/                       # Committed copy from toon-format/spec @ SPEC_COMMIT
    encode/                       # Committed copy from toon-format/spec @ SPEC_COMMIT
```

> Note: No `lib/toon/types.ex`. Public `@type` declarations live inside `lib/toon.ex`;
> internal types live inside the modules that own them.

## Testing

### Conformance Tests (Priority 1)

Fixtures are copied into `test/fixtures/` from a pinned `toon-format/spec` commit
SHA recorded in `test/fixtures/SPEC_COMMIT.txt`. Do NOT fetch at test time —
fixtures must be committed to the repository for reproducible CI runs. When a
fixture file is added or removed, run `touch test/toon/conformance_test.exs &&
mix test` to force recompilation (`@external_resource` does not observe new
files matched by `Path.wildcard/1`).

Use the 22 language-agnostic JSON fixtures from `toon-format/spec/tests/fixtures/`:

**Decode fixtures (13 files):**
- `arrays-nested.json`, `arrays-primitive.json`, `arrays-tabular.json`
- `blank-lines.json`, `delimiters.json`, `indentation-errors.json`
- `numbers.json`, `objects.json`, `path-expansion.json`
- `primitives.json`, `root-form.json`, `validation-errors.json`, `whitespace.json`

**Encode fixtures (9 files):**
- `arrays-nested.json`, `arrays-objects.json`, `arrays-primitive.json`, `arrays-tabular.json`
- `delimiters.json`, `key-folding.json`, `objects.json`, `primitives.json`, `whitespace.json`

**Fixture structure reference:**
```json
{
  "version": "1.4",
  "category": "decode",
  "tests": [
    { "name": "parses safe unquoted string", "input": "hello", "expected": "hello" },
    { "name": "rejects bad indent", "input": "key:\n  a\n b", "error": true }
  ]
}
```
- `"input"`: for decode fixtures — a raw TOON string; for encode fixtures — a JSON value
  (object/array/primitive), parsed at compile time by `Jason.decode!`.
- `"expected"`: for decode — the expected decoded value; for encode — the expected TOON string.
- `"error": true` marks **negative tests**: the operation must fail with a structured error,
  not return `{:ok, _}`. Files containing error cases: `validation-errors.json`,
  `indentation-errors.json`. The conformance test harness MUST branch on this field.

### Unit Tests

```elixir
describe "Toon.encode/2" do
  test "encodes flat object" do
    # Maps are encoded in sorted-key order (deterministic).
    assert {:ok, result} = Toon.encode(%{"age" => 30, "name" => "Alice"})
    assert result == "age: 30\nname: Alice"
  end

  test "encodes uniform array as tabular" do
    input = %{"users" => [%{"id" => 1, "name" => "Alice"}, %{"id" => 2, "name" => "Bob"}]}
    assert {:ok, result} = Toon.encode(input)
    assert result == "users[2]{id,name}:\n  1,Alice\n  2,Bob"
  end

  test "encodes primitive array inline" do
    assert {:ok, result} = Toon.encode(%{"tags" => ["a", "b", "c"]})
    assert result == "tags[3]: a,b,c"
  end

  test "normalizes atom keys" do
    assert {:ok, result} = Toon.encode(%{name: "Alice"})
    assert result == "name: Alice"
  end

  test "quotes strings that need quoting" do
    assert {:ok, result} = Toon.encode(%{"val" => "true"})
    assert result == ~s(val: "true")
  end

  test "returns error tuple for unencodable term" do
    assert {:error, %Toon.EncodeError{reason: :unencodable_term}} = Toon.encode(self())
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

  test "returns structured error for non-binary input" do
    # Non-binary inputs must return {:error, DecodeError} not raise FunctionClauseError.
    assert {:error, %Toon.DecodeError{reason: :invalid_input}} = Toon.decode(:not_a_string)
    assert {:error, %Toon.DecodeError{reason: :invalid_input}} = Toon.decode(123)
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
git commit -m "chore: verify hex.pm package name availability (#1)"
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
- [ ] Streaming encode via `encode_lines/2` returns a correct `Enumerable.t()` (raises on
      encoding failure — does NOT return `{:error, _}`; documented in function docstring)
- [ ] `decode_from_lines/2` correctly decodes `File.stream!/1` input
- [ ] Atom-keyed maps normalized correctly in encoder
- [ ] Keyword lists preserved in original order during encoding
- [ ] Plain maps encoded with deterministic (sorted-key) output
- [ ] Custom structs encoded via `Toon.Encodable` protocol (with default `Map.from_struct/1`)
- [ ] `decode/2` returns `{:error, %Toon.DecodeError{reason: :invalid_input}}` for non-binary input
      (no `FunctionClauseError` leaks — fallback clause returns structured error)
- [ ] `decode/2` returns `{:error, %Toon.DecodeError{line: _, reason: _}}` on malformed TOON input
- [ ] `encode/2` returns `{:ok, String.t()}` on success, `{:error, %Toon.EncodeError{}}` on
      unencodable terms (pids, functions, duplicate keys, etc.)
- [ ] `encode!/2` unwraps-or-raises; `decode!/2` unwraps-or-raises
- [ ] LICENSE file present; `mix hex.build` produces no license warnings
- [ ] `test/fixtures/SPEC_COMMIT.txt` records pinned spec SHA
- [ ] CRLF input decoded identically to LF input
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
- **Hex.pm name availability:** Before first publish, run `mix hex.search toon` and
  `curl https://hex.pm/api/packages/toon`. If `:toon` is taken, fall back to
  `:toon_format` or `:toon_ex` via `package: [name: :toon_format]` while keeping the
  local `app:` atom stable
- **Fixture pinning:** `test/fixtures/SPEC_COMMIT.txt` records the exact
  `toon-format/spec` commit SHA used. Fixtures are committed to the repo, not
  fetched at test time. Updating the pin is a deliberate versioned action

## Follow-up Tasks

1. Submit to `toon-format` organization as official Elixir implementation
2. Consider `Toon.Sigil` (`~TOON`) for compile-time TOON decoding in tests
3. Benchmark vs Jason for LLM prompt construction workflows
4. Add a lazy `decode_stream/2` once a concrete consumer requires per-event streaming
5. Add `NimbleOptions`-based option schema validation for better error messages
6. Add property-based round-trip tests via `:stream_data` (generate arbitrary
   `json_value()`, assert `encode |> decode == original`)

> Note: `encode!/2`, `decode!/2`, and the `Toon.Encodable` protocol were moved from
> Follow-up into the v0.1 Solution per Round 1a architecture review.
