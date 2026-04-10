defprotocol Toon.Encodable do
  @moduledoc """
  Protocol for converting custom Elixir structs into the TOON data model. Modeled
  after `Jason.Encoder`. Implementations must return a value that is itself
  encodable (map, list, keyword, primitive).

  The encoder only invokes this protocol when the input satisfies `is_struct/1`.
  Non-struct terms are handled directly by Normalize. There is no
  `@fallback_to_any`: the default for structs without an implementation is
  `Map.from_struct/1`, invoked by Normalize, not by the protocol.

  Example implementation:

      defimpl Toon.Encodable, for: MyApp.User do
        # Return only the fields safe to encode; exclude sensitive fields.
        def to_toon(%MyApp.User{id: id, name: name}) do
          %{"id" => id, "name" => name}
        end
      end

  Note: `@derive {Toon.Encodable, only: [...]}` is not supported in v0.1.
  Implement the protocol manually with `defimpl`.
  """

  @spec to_toon(struct()) :: term()
  def to_toon(value)
end
