# instructor_ex

_Structured, Ecto outputs with OpenAI (and OSS LLMs)_

---

[![Instructor version](https://img.shields.io/hexpm/v/instructor.svg)](https://hex.pm/packages/instructor)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/instructor/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/instructor)](https://hex.pm/packages/instructor)
[![GitHub stars](https://img.shields.io/github/stars/thmsmlr/instructor_ex.svg)](https://github.com/thmsmlr/instructor_ex/stargazers)
[![Twitter Follow](https://img.shields.io/twitter/follow/thmsmlr?style=social)](https://twitter.com/thmsmlr)
[![Discord](https://img.shields.io/discord/1192334452110659664?label=discord)](https://discord.gg/CV8sPM5k5Y)

<!-- Docs -->

 Structured prompting for LLMs. Instructor is a spiritual port of the great [Instructor Python Library](https://github.com/jxnl/instructor) by [@jxnlco](https://twitter.com/jxnlco), check out his [talk on YouTube](https://www.youtube.com/watch?v=yj-wSRJwrrc).
 
 The Instructor library is useful for coaxing an LLM to return JSON that maps to an Ecto schema that you provide, rather than the default unstructured text output. If you define your own validation logic, Instructor can automatically retry prompts when validation fails (returning natural language error messages to the LLM, to guide it when making corrections).

Instructor is designed to be used with the [OpenAI API](https://platform.openai.com/docs/api-reference/chat-completions/create) by default, but it also works with [llama.cpp](https://github.com/ggerganov/llama.cpp) and [Bumblebee](https://github.com/elixir-nx/bumblebee) (Coming Soon!) by using an extendable adapter behavior.

At its simplest, usage is pretty straightforward: 

1. Create an ecto schema, with a `@doc` string that explains the schema definition to the LLM. 
2. Define a `validate_changeset/1` function on the schema, and use the `Instructor.Validator` macro in order for Instructor to know about it.
2. Make a call to `Instructor.chat_completion/1` with an instruction for the LLM to execute.

You can use the `max_retries` parameter to automatically, iteratively go back and forth with the LLM to try fixing validation errorswhen they occur.

```elixir
defmodule SpamPrediction do
  use Ecto.Schema
  use Instructor.Validator

  @doc """
  ## Field Descriptions:
  - class: Whether or not the email is spam.
  - reason: A short, less than 10 word rationalization for the classification.
  - score: A confidence score between 0.0 and 1.0 for the classification.
  """
  @primary_key false
  embedded_schema do
    field(:class, Ecto.Enum, values: [:spam, :not_spam])
    field(:reason, :string)
    field(:score, :float)
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_number(:score,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
  end
end

is_spam? = fn text ->
  Instructor.chat_completion(
    model: "gpt-3.5-turbo",
    response_model: SpamPrediction,
    max_retries: 3,
    messages: [
      %{
        role: "user",
        content: """
        Your purpose is to classify customer support emails as either spam or not.
        This is for a clothing retail business.
        They sell all types of clothing.

        Classify the following email: 
        ```
        #{text}
        ```
        """
      }
    ]
  )
end

is_spam?.("Hello I am a Nigerian prince and I would like to send you money")

# => {:ok, %SpamPrediction{class: :spam, reason: "Nigerian prince email scam", score: 0.98}}
```

Check out our [Quickstart Guide](https://hexdocs.pm/instructor/quickstart.html) for more code snippets that you can run locally (in Livebook). Or, to get a better idea of the thinking behind Instructor, read more about our [Philosophy & Motivations](https://hexdocs.pm/instructor/philosophy.html).

Optionally, you can also customize the your llama.cpp calls (with defaults shown):
```elixir
llamacpp
config :instructor, adapter: Instructor.Adapters.Llamacpp
config :instructor, :llamacpp,
    chat_template: :mistral_instruct,
    api_url: "http://localhost:8080/completion"
````

<!-- Docs -->

## Installation

In your mix.exs,

```elixir
def deps do
  [
    {:instructor, "~> 0.0.5"}
  ]
end
```

InstructorEx uses [Code.fetch_docs/1](https://hexdocs.pm/elixir/1.16.2/Code.html#fetch_docs/1) to fetch LLM instructions from the Ecto schema specified in `response_model`. If your project is deployed using [releases](https://hexdocs.pm/mix/Mix.Tasks.Release.html), add the following configuration to mix.exs to prevent docs from being stripped from the release:

```elixir
def project do
  # ...
  releases: [
    myapp: [
      strip_beams: [keep: ["Docs"]]
    ]
  ]
end
```

## TODO

- [ ] Partial Schemaless doesn't work since fields are set to required in Ecto.
- [ ] Groq adapter
- [ ] ChainOfThought doesn't work with max_retries
- [ ] Logging for Distillation / Finetuning
- [ ] Add a Bumblebee adapter
- [ ] Support naked ecto types by auto-wrapping, not just maps of ecto types, do not wrap if we don't need to... Current codepaths are muddled
- [ ] Optional/Maybe types
- [ ] Add Livebook Tutorials, include in Hexdocs
    - [x] Text Classification
    - [ ] Self Critique
    - [ ] Image Extracting Tables
    - [ ] Moderation
    - [x] Citations
    - [ ] Knowledge Graph
    - [ ] Entity Resolution
    - [ ] Search Queries
    - [ ] Query Decomposition
    - [ ] Recursive Schemas
    - [x] Table Extraction
    - [x] Action Item and Dependency Mapping
    - [ ] Multi-File Code Generation
    - [ ] PII Data Sanitizatiommersed
- [x] Update hexdocs homepage to include example for tutorial

## Blog Posts

- [ ] Why structured prompting?

    Meditations on new HCI.
    Finally we have software that can understand text. f(text) -> text.
    This is great, as it gives us a new domain, but the range is still text.
    While we can use string interpolation to map Software 1.0 into f(text), the outputs are not interoperable with Software 1.0.
    Hence why UXs available to us are things like Chatbots as our users have to interpret the output.

    Instructor, structure prompting, gives use f(text) -> ecto_schema.
    Schemas are the lingua franca of Software 1.0.
    With Instrutor we can now seamlessly move back and forth between Software 1.0 and Software 2.0.

    Now we can maximally leverage AI...

- [ ] From GPT-4 to zero-cost production - Distilation, local-llms, and the cost structure of AI.

    ... 😘
