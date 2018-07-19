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
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    A mix task that automatically fixes compiler warnings: prefixes unused variables, removes unused aliases, removes unused imports.
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
