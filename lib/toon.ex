defmodule Toon do
  @moduledoc """
  Token-Oriented Object Notation (TOON) encoder/decoder for Elixir.

  Spec-conformant with TOON v3.0. Provides encode/decode with support for
  all TOON array forms (inline primitive, tabular, expanded list), key folding,
  path expansion, and strict-mode validation.

  ## Quick start

      # Encode a map to TOON
      {:ok, toon} = Toon.encode(%{"name" => "Alice", "age" => 30})

      # Decode TOON to a map
      {:ok, value} = Toon.decode("name: Alice\\nage: 30")

  ## Key ordering

  Elixir maps do not preserve insertion order. For deterministic output that
  matches your intended field order, pass a keyword list or a list of
  `{binary, value}` tuples instead of a plain map.
  """

  alias Toon.{DecodeError, EncodeError}

  # ---------------------------------------------------------------------------
  # Public types
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Encode
  # ---------------------------------------------------------------------------

  @doc """
  Encode an Elixir value as a TOON document string.

  Returns `{:ok, string}` on success or `{:error, %Toon.EncodeError{}}` when
  the input contains an unencodable term (function, PID, reference, port) or
  duplicate keys in a tuple-list object.

  ## Options

    * `:indent` — spaces per indent level (default `2`)
    * `:delimiter` — field delimiter: `:comma`, `:tab`, or `:pipe` (default `:comma`)
    * `:key_folding` — collapse single-key object chains: `:off` or `:safe` (default `:off`)
    * `:flatten_depth` — maximum nesting depth for array expansion (default `:infinity`)
    * `:replacer` — `(key, value, path) -> value | :skip` transform callback
  """
  @spec encode(term(), encode_opts()) :: {:ok, String.t()} | {:error, EncodeError.t()}
  def encode(input, opts \\ []) do
    # Validate outside try — unknown option keys are programmer errors (ArgumentError),
    # not runtime encode failures that belong in the {:error, _} return path.
    opts =
      Keyword.validate!(opts, [:indent, :delimiter, :key_folding, :flatten_depth, :replacer])

    try do
      # encode_value/3 returns iodata() for efficiency; flatten here.
      iodata = Toon.Encoder.Core.encode_value(input, opts, [])
      {:ok, IO.iodata_to_binary(iodata)}
    rescue
      e in EncodeError -> {:error, e}
    end
  end

  @doc """
  Encode an Elixir value as a TOON document string, raising on failure.

  See `encode/2` for options. Raises `Toon.EncodeError` when encoding fails.
  """
  @spec encode!(term(), encode_opts()) :: String.t()
  def encode!(input, opts \\ []) do
    case encode(input, opts) do
      {:ok, string} -> string
      {:error, %EncodeError{} = err} -> raise err
    end
  end

  # ---------------------------------------------------------------------------
  # Decode
  # ---------------------------------------------------------------------------

  @doc """
  Decode a TOON document string into an Elixir value.

  Returns `{:ok, value}` on success or `{:error, %Toon.DecodeError{}}` on
  malformed input. CRLF line endings are normalized before processing.

  ## Options

    * `:strict` — enable strict-mode validation (default `true`)
    * `:expand_paths` — expand dotted keys into nested maps: `:off` or `:safe` (default `:off`)
  """
  @spec decode(String.t(), decode_opts()) :: {:ok, json_value()} | {:error, DecodeError.t()}
  def decode(input, opts \\ [])

  def decode(input, opts) when is_binary(input) do
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

  @doc """
  Decode a TOON document string, raising on failure.

  See `decode/2` for options. Raises `Toon.DecodeError` when decoding fails.
  """
  @spec decode!(String.t(), decode_opts()) :: json_value()
  def decode!(input, opts \\ []) do
    case decode(input, opts) do
      {:ok, value} -> value
      {:error, %DecodeError{} = err} -> raise err
    end
  end

  # ---------------------------------------------------------------------------
  # Streaming
  # ---------------------------------------------------------------------------

  @doc """
  Encode an Elixir value as a lazy stream of TOON line binaries.

  Unlike `encode/2`, this function does NOT return `{:error, _}` — encoding
  failures raise `Toon.EncodeError` during stream enumeration. Use `encode/2`
  for error-safe encoding.

  ## Options

  Same as `encode/2`.
  """
  @spec encode_lines(term(), encode_opts()) :: Enumerable.t()
  def encode_lines(input, opts \\ []) do
    opts =
      Keyword.validate!(opts, [:indent, :delimiter, :key_folding, :flatten_depth, :replacer])

    Toon.Encoder.Core.encode_lines(input, opts)
  end

  @doc """
  Decode an `Enumerable.t()` of line binaries into an Elixir value.

  Accepts any enumerable of `String.t()` lines — typically `File.stream!/1`,
  `IO.stream/2`, or a plain list. Returns `{:ok, value}` or
  `{:error, %Toon.DecodeError{}}`.

  ## Options

  Same as `decode/2`.
  """
  @spec decode_from_lines(Enumerable.t(), decode_opts()) ::
          {:ok, json_value()} | {:error, DecodeError.t()}
  def decode_from_lines(lines, opts \\ []) do
    opts = Keyword.validate!(opts, [:strict, :expand_paths])
    Toon.Decoder.Core.decode_lines(lines, opts)
  end

  @doc """
  Decode an `Enumerable.t()` of line binaries into a list of stream events.

  Returns an `Enumerable.t()` of event maps. Raises `Toon.DecodeError` on
  malformed input or strict-mode violations. This is a synchronous implementation
  intended for testing and inspection of the raw parse event stream.

  ## Options

    * `:strict` — enable strict-mode validation (default `false`)
  """
  @spec decode_stream_sync(Enumerable.t(), keyword()) :: Enumerable.t()
  def decode_stream_sync(lines, opts \\ []) do
    opts = Keyword.validate!(opts, [:strict])
    Toon.Decoder.DecodeStreamSync.decode(lines, opts)
  end
end
