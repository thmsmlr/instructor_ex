# instructor_ex

_Structured, Ecto outputs with OpenAI (and OSS LLMs)_

---

[![KinoShell version](https://img.shields.io/hexpm/v/instructor_ex.svg)](https://hex.pm/packages/instructor_ex)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/instructor_ex/)
[![GitHub stars](https://img.shields.io/github/stars/thmsmlr/instructor_ex.svg)](https://github.com/thmsmlr/instructor_ex/stargazers)
[![Twitter Follow](https://img.shields.io/twitter/follow/thmsmlr?style=social)](https://twitter.com/thmsmlr)


Instructor.ex is a spiritual port of the great [Instructor Python Library](https://github.com/jxnl/instructor) by [@jxnlco](https://twitter.com/jxnlco).
This library brings structured prompting to LLMs. Instead of receiving text as output, Instructor will coax the LLM to output valid JSON that maps directly to the provided Ecto schema.
If the LLM fails to do so, or provides values that do not pass your validations, it will provide you utilities to automatically retry with the LLM to correct errors.
By default it's designed to be used with the [OpenAI API](https://platform.openai.com/docs/api-reference/chat-completions/create), however it provides an extendable adapter behavior to work with [ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp) and [Bumblebee (Coming Soon!)](https://github.com/elixir-nx/bumblebee).

At it's simplest, usage is pretty straight forward,

```elixir
defmodule SpamPredicition do
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

# => {:ok, %SpamPredicition{class: :spam, reason: "Nigerian prince email scam", score: 0.98}}
```

Simply create an ecto schema, optionally provide a `@doc` to the schema definition which we pass down to the LLM, then make a call to `Instructor.chat_completion/1` with contect about the task you'd like the LLM to complete.

## Installation

```elixir
def deps do
  [
    {:instructor, "~> 0.0.1"}
  ]
end
```

## TODO

- [x] Tests
    - [x] JSONSchema
    - [x] gbnf
- [x] Add JSONSchema --> GBNF computation
- [x] Add field descriptions
- [x] Add validators
- [ ] Cleanup large with, add typespecs and docs
- [ ] Retry Logic
- [ ] llamacpp should handle all messages values, not just first system and first user
- [ ] Support binaries and binary_id in JSONSchema and GBNF
- [ ] Verify :naive_datetime support
