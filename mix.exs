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
          "pages/quickstart.livemd",
          "pages/philosophy.md",
          "pages/llm-providers/llama-cpp.livemd",
          "pages/llm-providers/ollama.livemd",
          "pages/cookbook/text-classification.livemd",
          "pages/cookbook/qa-citations.livemd",
          "pages/cookbook/extract-action-items-from-meeting-transcripts.livemd",
          "pages/cookbook/text-to-dataframes.livemd"
        ],
        groups_for_extras: [
          "LLM Providers": ~r"pages/llm-providers/.*\.(md|livemd)",
          Cookbook: ~r"pages/cookbook/.*\.(md|livemd)"
        ],
        before_closing_body_tag: &before_closing_body_tag/1
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

  def before_closing_body_tag(:html) do
    """
    <script src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      document.addEventListener("DOMContentLoaded", function () {
        mermaid.initialize({
          startOnLoad: false,
          theme: document.body.className.includes("dark") ? "dark" : "default"
        });
        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  def before_closing_body_tag(_), do: ""

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.11"},
      {:jason, "~> 1.4.0"},
      {:req, "~> 0.4.0"},
      {:jaxon, "~> 2.0"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:mox, "~> 1.1.0", only: :test}
    ]
  end
end
