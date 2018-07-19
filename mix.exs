defmodule Fixer.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_fixer,
      version: "1.0.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end

  defp description do
    """
    A mix task that automatically fixes compiler warnings: removes unused aliases, prefixes unused variables.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Denis Gorbachev"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/DenisGorbachev/ex_fixer"}
    ]
  end
end
