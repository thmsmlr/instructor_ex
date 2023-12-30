defmodule Instructor.MixProject do
  use Mix.Project

  @external_resource "README.md"
  @version "README.md"
           |> File.read!()
           |> then(&Regex.run(~r/{:instructor, "~> (\d+\.\d+\.\d+)"}/, &1))
           |> List.last()

  def project do
    [
      app: :instructor,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),

      # Docs
      name: "Instructor",
      source_url: "https://github.com/thmsmlr/instructor_ex",
      homepage_url: "https://github.com/thmsmlr/instructor_ex",
      docs: [
        main: "Instructor",
        extras: [
          "README.md",
          "notebooks/tutorial.livemd"
        ],
        extra_section: "GUIDES",
      ],
      package: package()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "Structured prompting for OpenAI and OSS LLMs"
  end

  defp package do
    [
      maintainers: ["Thomas Millar"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/thmsmlr/instructor_ex"
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:ecto, "~> 3.11"},
      {:openai, "~> 0.6.0"},
      {:jason, "~> 1.4.0"},
      {:req, "~> 0.4.0"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
