# Changelog

## [Unreleased](https://github.com/thmsmlr/instructor_ex/compare/v0.0.5..main)

...

## [v0.1.0](https://github.com/thmsmlr/instructor_ex/compare/v0.0.5..v0.1.0)

### Added
- **New Adapters**: Anthropic, Gemini, xAI,Groq, Ollama, and VLLM. Each of these provides specialized support for their respective LLM APIs.
- **`:json_schema` Mode**: The OpenAI adapter and others now support a `:json_schema` mode for more structured JSON outputs.
- **`Instructor.Extras.ChainOfThought`**: A new module to guide multi-step reasoning processes with partial returns and final answers.
- **Enhanced Streaming**: More robust partial/array streaming pipelines, plus improved SSE-based parsing for streamed responses.
- **Re-ask/Follow-up Logic**: Adapters can now handle re-asking the LLM to correct invalid JSON responses when `max_retries` is set.

### Changed
- **OpenAI Adapter Refactor**: A major internal refactor for more flexible streaming modes, additional “response format” options, and better error handling.
- **Ecto Dependency**: Updated from `3.11` to `3.12`. 
- **Req Dependency**: Now supports `~> 0.5` or `~> 1.0`.

### Deprecated
- **Schema Documentation via `@doc`**: Schemas using `@doc` to send instructions to the LLM will now emit a warning. Please migrate to `@llm_doc` via `use Instructor`.

### Breaking Changes
- Some adapter configurations now require specifying an `:api_path` or `:auth_mode`. Verify your adapter config matches the new format.
- The OpenAI adapter’s `:json_schema` mode strips unsupported fields (e.g., `format`, `pattern`) from schemas before sending them to the LLM.

### Fixed
- Various improvements to JSON parsing and streaming handling, including better handling of partial/invalid responses.


## [v0.0.5](https://github.com/thmsmlr/instructor_ex/compare/v0.0.4..v0.0.5)

### Added

- Support for [together.ai](https://together.ai) inference server
- Support for [ollama](https://ollama.com) local inference server
- GPT-4 Vision support
- Added `:json` and `:md_json` modes to support more models and inference servers

### Changed

- Default http settings and where they are stored

before:
```elixir
config :openai, http_options: [...]
```

after:
```elixir
config :instructor, :openai, http_options: [...]
```

### Removed

- OpenAI client to allow for better control of default settings and reduce dependencies


## [v0.0.4](https://github.com/thmsmlr/instructor_ex/compare/v0.0.3...v0.0.4) - 2024-01-15

### Added

- `Instructor.Adapters.Llamacpp` for running instructor against local llms.
- `use Instructor.EctoType` for supporting custom ecto types.
- More documentation

### Fixed

- Bug fixes in ecto --> json_schema --> gbnf grammar pipeline, added better tests


## [v0.0.3](https://github.com/thmsmlr/instructor_ex/compare/v0.0.2...v0.0.3) - 2024-01-10

### Added

- Schemaless Ecto support
- `response_model: {:partial, Model}` partial streaming mode
- `response_model: {:array, Model}` record streaming mode

### Fixed

- Bug handling nested module names

## [v0.0.2](https://github.com/thmsmlr/instructor_ex/compare/v0.0.1...v0.0.2) - 2023-12-30

### Added

- `use Instructor.Validator` for validation callbacks on your Ecto Schemas
- `max_retries:` option to reask the LLM to fix any validation errors

## [v0.0.1](https://github.com/thmsmlr/instructor_ex/compare/v0.0.1...v0.0.1) - 2023-12-19

### Added

- Structured prompting with LLMs using Ecto
