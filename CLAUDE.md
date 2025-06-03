# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Instructor is an Elixir library for structured prompting with Large Language Models. It converts LLM text outputs into validated Ecto structs, enabling seamless integration between AI and traditional Elixir applications.

## Essential Commands

### Development
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix test` - Run all tests
- `mix test test/specific_test.exs` - Run a specific test file
- `mix docs` - Generate documentation (includes image copying)

### Testing
- Use `Mox` for mocking HTTP requests in tests
- Test files mirror the lib/ structure
- Integration tests in `instructor_test.exs` cover all adapters
- MockOpenAI adapter in `test/support/` for deterministic testing

## Architecture

### Core Components
- **Instructor** (`lib/instructor.ex`) - Main API with `chat_completion/2` function
- **Adapter Pattern** (`lib/instructor/adapter.ex`) - Pluggable LLM providers (OpenAI, Anthropic, Gemini, Groq, Llamacpp, Ollama, VLLM)
- **JSON Schema Generator** (`lib/instructor/json_schema.ex`) - Converts Ecto schemas to JSON Schema for LLM instructions
- **Validator** (`lib/instructor/validator.ex`) - Ecto-based validation with automatic retry logic
- **Streaming Parsers** - Handle partial JSON and SSE parsing for real-time responses

### Response Modes
- `:tools` - OpenAI function calling (most reliable)
- `:json` - OpenAI JSON mode
- `:json_schema` - OpenAI structured outputs
- `:md_json` - JSON in markdown code blocks

### Schema Patterns
```elixir
defmodule YourSchema do
  use Ecto.Schema
  use Instructor.Validator

  @llm_doc """
  Description for the LLM explaining this schema
  """
  
  embedded_schema do
    field(:field_name, :type)
  end

  @impl true
  def validate_changeset(changeset) do
    # Custom validation logic
  end
end
```

### Streaming Support
- **Partial streaming**: Emits incomplete objects as they build up
- **Array streaming**: Emits complete objects from arrays one at a time
- Use `{:partial, schema}` or `{:array, schema}` response models

## Key Files

- `lib/instructor.ex:1` - Main API entry point
- `lib/instructor/adapter.ex:1` - Adapter behavior definition
- `lib/instructor/adapters/*.ex` - LLM provider implementations
- `lib/instructor/json_schema.ex:1` - Schema-to-JSON conversion
- `lib/instructor/validator.ex:1` - Validation framework
- `test/support/test_helpers.ex:1` - Testing utilities

## Configuration

Set adapter in config:
```elixir
config :instructor, adapter: Instructor.Adapters.OpenAI  # default
```

Provider-specific config:
```elixir
config :instructor, :llamacpp,
  chat_template: :mistral_instruct,
  api_url: "http://localhost:8080/completion"
```

## Validation & Retry Logic

- Validation failures automatically retry with error feedback to LLM
- Use `max_retries` parameter to control retry attempts
- `validate_with_llm/3` enables LLM-based validation
- All validation happens through Ecto changesets

## Release Considerations

Add to `mix.exs` for releases to preserve documentation:
```elixir
releases: [
  myapp: [
    strip_beams: [keep: ["Docs"]]
  ]
]
```