defmodule Procrastinator.Mixfile do
  use Mix.Project

  def project do
    [app: :procrastinator,
     version: "0.1.1",
     description: description(),
     package: package(),
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     docs: [extras: ["README.md"]]]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:credo, "~> 0.4.12", only: [:dev, :test]},
     {:ex_doc, "~> 0.11", only: :dev}]
  end

  defp description do
    """
    Procrastinates work until the last second or until the work load has gotten
    so big that it has to do it. Just like people!
    """
  end

  defp package do
    [
      maintainers: ["Trevor Fenn", "Podium"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Podium/procrastinator"}
    ]
  end
end
