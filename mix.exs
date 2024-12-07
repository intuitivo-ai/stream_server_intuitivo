defmodule StreamServerIntuitivo.MixProject do
  use Mix.Project

  def project do
    [
      app: :mjpeg_server,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MjpegServer, []}
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.5"},
      {:jason, "~> 1.2"}
    ]
  end
end
