defimpl Toon.Encodable, for: DateTime do
  @doc false
  def to_toon(dt), do: DateTime.to_iso8601(dt)
end

defimpl Toon.Encodable, for: Date do
  @doc false
  def to_toon(d), do: Date.to_iso8601(d)
end

defimpl Toon.Encodable, for: MapSet do
  @doc false
  def to_toon(ms), do: ms |> MapSet.to_list() |> Enum.sort()
end
