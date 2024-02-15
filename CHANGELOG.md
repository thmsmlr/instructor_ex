# Changelog

## [Unreleased](https://github.com/thmsmlr/instructor_ex/compare/v0.0.4..main)

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
