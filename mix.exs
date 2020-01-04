defmodule EctoTransit.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_transit,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    []
  end

  defp deps do
    []
  end
end