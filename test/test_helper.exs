Mox.defmock(InstructorTest.MockOpenAI, for: Instructor.Adapter)

# Exclude the unmocked tests by default, to run them use:
#
#   mix test --only adapter:llamacpp
#   mix test --only adapter:openai
#
# to run all the non-local models, use:
#
#   mix test --include adapter:gemini --include adapter:anthropic --include adapter:openai
#
#
ExUnit.configure(
  exclude: [
    adapter: :openai,
    adapter: :groq,
    adapter: :anthropic,
    adapter: :gemini,
    adapter: :xai,
    adapter: :llamacpp,
    adapter: :ollama
  ]
)

ExUnit.start()
