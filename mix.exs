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
      source_url: "https://github.com/KirillTemnov/elixir-toon"
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
        "GitHub" => "https://github.com/KirillTemnov/elixir-toon",
        "Spec" => "https://github.com/toon-format/spec",
        "Reference Implementation" => "https://github.com/toon-format/toon"
      },
      maintainers: ["Kirill Temnov"],
      # Explicit file list keeps test fixtures out of the published Hex package.
      # test/fixtures/ (22 JSON conformance files) is intentionally excluded.
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "Toon",
      extras: ["README.md", "CHANGELOG.md"],
      source_url_pattern:
        "https://github.com/KirillTemnov/elixir-toon/blob/main/%{path}#L%{line}"
    ]
  end
end
