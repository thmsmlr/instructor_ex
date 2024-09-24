Mox.defmock(InstructorTest.MockOpenAI, for: Instructor.Adapter)

# Exclude the unmocked tests by default, to run them use:
#
#   mix test --only adapter:llamacpp
#   mix test --only adapter:openai
#
ExUnit.configure(exclude: [adapter: :llamacpp, adapter: :openai])

ExUnit.start()
