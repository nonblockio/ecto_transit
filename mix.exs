defmodule EctoTransit.MixProject do
  use Mix.Project

  @version "0.1.0"
  @name "EctoTransit"

  def project do
    [
      app: :ecto_transit,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: @name,
      docs: [
        main: @name,
        source_url: "https://github.com/nonblockio/ecto_transit"
      ]
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ecto, ">= 3.0.0"},
      {:ecto_enum, ">= 1.2.0", only: :test},
      {:ex_doc, "~> 0.21", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A transition validator for Ecto and EctoEnum."
  end

  defp package do
    [
      maintainers: ["nonblockio"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/nonblockio/ecto_transit"}
    ]
  end
end
