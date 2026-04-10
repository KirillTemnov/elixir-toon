# Toon

[![Hex.pm](https://img.shields.io/hexpm/v/toon.svg)](https://hex.pm/packages/toon)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](./LICENSE)
[![SPEC v3.0](https://img.shields.io/badge/spec-v3.0-blue)](https://github.com/toon-format/spec)

Elixir implementation of [Token-Oriented Object Notation (TOON) v3.0](https://github.com/toon-format/spec) — a compact, human-readable encoding of JSON designed to minimize LLM prompt tokens.

TOON uses ~40% fewer tokens than standard JSON for uniform structured data while maintaining higher LLM comprehension accuracy.

## Installation

```elixir
def deps do
  [{:toon, "~> 0.1"}]
end
```

## Quick Start

```elixir
# Encode
{:ok, toon} = Toon.encode(%{
  "context" => %{"task" => "Our favorite hikes", "location" => "Boulder"},
  "friends" => ["ana", "luis", "sam"],
  "hikes" => [
    %{"id" => 1, "name" => "Blue Lake Trail", "km" => 7.5, "sunny" => true},
    %{"id" => 2, "name" => "Ridge Overlook", "km" => 9.2, "sunny" => false}
  ]
})
# =>
# context:
#   location: Boulder
#   task: Our favorite hikes
# friends[3]: ana,luis,sam
# hikes[2]{id,km,name,sunny}:
#   1,7.5,Blue Lake Trail,true
#   2,9.2,Ridge Overlook,false

# Decode
{:ok, data} = Toon.decode(toon)
```

## API

### `Toon.encode/2`

```elixir
@spec encode(term(), keyword()) :: {:ok, String.t()} | {:error, Toon.EncodeError.t()}
```

Encodes an Elixir term to a TOON string.

**Options:**
- `:indent` — spaces per indent level (default `2`)
- `:delimiter` — field delimiter: `:comma`, `:tab`, or `:pipe` (default `:comma`)
- `:key_folding` — collapse single-key chains into dotted paths: `:off` or `:safe` (default `:off`)
- `:flatten_depth` — maximum nesting depth for array expansion (default `:infinity`)
- `:replacer` — `(key, value, path) -> :keep | :skip | {:replace, val}` transform callback

### `Toon.decode/2`

```elixir
@spec decode(String.t(), keyword()) :: {:ok, term()} | {:error, Toon.DecodeError.t()}
```

Decodes a TOON string. CRLF line endings are normalized automatically.

**Options:**
- `:strict` — enable strict-mode validation (default `true`)
- `:expand_paths` — expand dotted keys into nested maps: `:off` or `:safe` (default `:off`)

### Bang variants

`encode!/2` and `decode!/2` unwrap `{:ok, value}` or raise on error.

### Streaming

```elixir
# Lazy encode — yields one line binary at a time
for line <- Toon.encode_lines(data) do
  IO.puts(line)
end

# Decode from file stream (no trailing newlines needed)
File.stream!("data.toon")
|> Stream.map(&String.trim_trailing(&1, "\n"))
|> Toon.decode_from_lines()
```

### Key ordering

Elixir maps do not preserve insertion order. To control field order in the output:

```elixir
# Map — keys sorted alphabetically (deterministic)
Toon.encode(%{"zebra" => 1, "apple" => 2})
# => "apple: 2\nzebra: 1"

# Keyword list — order preserved
Toon.encode([{"zebra", 1}, {"apple", 2}])
# => "zebra: 1\napple: 2"

# Atom-keyed map — atoms normalized to strings, sorted alphabetically
Toon.encode(%{name: "Alice", age: 30})
# => "age: 30\nname: Alice"
```

### Custom struct encoding

```elixir
defimpl Toon.Encodable, for: MyApp.User do
  # Exclude sensitive fields; return only what should be encoded.
  def to_toon(%{id: id, name: name}) do
    %{"id" => id, "name" => name}
  end
end
```

Structs without a `Toon.Encodable` implementation fall back to `Map.from_struct/1`.

## Format Overview

```
# Flat object
name: Alice
age: 30

# Primitive array (inline)
tags[3]: elixir,otp,beam

# Uniform object array (tabular)
users[2]{id,name,active}:
  1,Alice,true
  2,Bob,false

# Nested object
config:
  db:
    host: localhost
    port: 5432

# Key folding (collapsed single-key chains)
config.db.host: localhost  # equivalent to the nested form above
```

## Conformance

This library passes all [toon-format/spec](https://github.com/toon-format/spec) conformance tests
(22 fixture files, pinned to commit recorded in `test/fixtures/SPEC_COMMIT.txt`).

## License

MIT — see [LICENSE](./LICENSE).
