# instructor_ex

_Structured, Ecto outputs with OpenAI (and OSS LLMs)_

---

[![Instructor version](https://img.shields.io/hexpm/v/instructor.svg)](https://hex.pm/packages/instructor)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/instructor/)
[![GitHub stars](https://img.shields.io/github/stars/thmsmlr/instructor_ex.svg)](https://github.com/thmsmlr/instructor_ex/stargazers)
[![Twitter Follow](https://img.shields.io/twitter/follow/thmsmlr?style=social)](https://twitter.com/thmsmlr)

<!-- Docs -->

Instructor.ex is a spiritual port of the great [Instructor Python Library](https://github.com/jxnl/instructor) by [@jxnlco](https://twitter.com/jxnlco), check out his [talk](https://www.youtube.com/watch?v=yj-wSRJwrrc) on youtube.
This library brings structured prompting to LLMs. Instead of receiving text as output, Instructor will coax the LLM to output valid JSON that maps directly to the provided Ecto schema.
If the LLM fails to do so, or provides values that do not pass your validations, it will provide you utilities to automatically retry with the LLM to correct errors.
By default it's designed to be used with the [OpenAI API](https://platform.openai.com/docs/api-reference/chat-completions/create), however it provides an extendable adapter behavior to work with [ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp) and [Bumblebee (Coming Soon!)](https://github.com/elixir-nx/bumblebee).

At its simplest, usage is pretty straightforward,

```elixir
defmodule SpamPrediction do
  use Ecto.Schema
  use Instructor.Validator

  @doc """
  ## Field Descriptions:
  - class: Whether or not the email is spam
  - reason: A short, less than 10 word rationalization for the classification
  - score: A confidence score between 0.0 and 1.0 for the classification
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
    response_model: SpamPredicition,
    max_retries: 3,
    messages: [
      %{
        role: "user",
        content: """
        You purpose is to classify customer support emails as either spam or not.
        This is for a clothing retailer business.
        They sell all types of clothing.

        Classify the following email: #{text}
        """
      }
    ]
  )
end

is_spam?.("Hello I am a Nigerian prince and I would like to send you money")

# => {:ok, %SpamPrediction{class: :spam, reason: "Nigerian prince email scam", score: 0.98}}
```

Simply create an ecto schema, optionally provide a `@doc` to the schema definition which we pass down to the LLM, then make a call to `Instructor.chat_completion/1` with context about the task you'd like the LLM to complete.
You can also provide a `validate_changeset/1` function via the `use Instructor.Validator` which will provide a set of code level ecto changeset validations. You can use this in conjunction with `max_retries: 3` to automatically, iteratively go back and forth with the LLM up to `n` times with any validation errors so that it has a chance to fix them.

**Curious to learn more? Unsure of how you'd use this? Check out our extensive set of [tutorials](https://hexdocs.pm/instructor/tutorial.html)**

## Configuration

To configure the default OpenAI adapter you can set the configuration,

```elixir
config :openai, api_key: "sk-........"
config :openai, http_options: [recv_timeout: 10 * 60 * 1000]
```

To use a local LLM, you can install and run [llama.cpp server](https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md) and tell instructor to use it,

```elixir
config :instructor, adapter: Instructor.Adapters.Llamacpp
```

<!-- Docs -->

## Installation

In your mix.exs,

```elixir
def deps do
  [
    {:instructor, "~> 0.0.2"}
  ]
end
```

## TODO

- [ ] llamacpp adapter broken, needs to support openai input/output API
  - [ ] GBNF should enforce required properties on objects, currently they're optional.
  - [ ] GBNF limit the number of digits in number tokens -- small models can sometimes run off to infinit digits
- [ ] Add `llm_validator`
- [ ] Logging for Distillation / Finetuning
- [ ] Add a Bumblebee adapter
- [ ] Add llamacpp_ex adapter
- [x] Support Streaming
  - [ ] Verify schemaless support `{:array, %{name: :string}}`
  - [ ] Support typespec style support for array streaming `[MySchema]`
- [ ] Optional/Maybe types
- [ ] When changeset fails to cast, it should show the underlying data (better error messages)
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
- [ ] Setup Github CI for testing, add badge to README

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
