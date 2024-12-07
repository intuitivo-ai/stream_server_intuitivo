defmodule StreamServerIntuitivo.MixProject do
  use Mix.Project

  def project do
    [
      app: :stream_server_intuitivo,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :plug_cowboy],
      mod: {StreamServerIntuitivo, []},
      start_phases: [init: []]
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.5"},
      {:jason, "~> 1.2"}
    ]
  end

  defp description do
    """
    A lightweight MJPEG streaming server for Elixir/Nerves projects.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/yourusername/stream_server_intuitivo"}
    ]
  end
end
