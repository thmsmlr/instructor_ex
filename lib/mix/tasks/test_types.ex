defmodule Mix.Tasks.Instructor.TestTypes do
  @moduledoc """
  Tests the custom Instructor types by generating a JSON schema for a test schema.

  ## Usage

      mix instructor.test_types
  """
  use Mix.Task

  @shortdoc "Tests the custom Instructor types"
  def run(_) do
    # Ensure all dependencies are started
    Mix.Task.run("app.start")

    # Define a test schema that uses our custom types
    defmodule TestSchema do
      use Ecto.Schema
      use Instructor

      @primary_key false
      embedded_schema do
        field :name, Instructor.Types.String,
          description: "The name of the test item",
          minLength: 3,
          maxLength: 50

        field :count, Instructor.Types.Integer,
          description: "The count of items",
          minimum: 0,
          maximum: 100

        field :status, Instructor.Types.Enum,
          values: ["active", "pending", "completed"],
          description: &__MODULE__.get_description/1
      end

      def get_description(context) do
        "This is a test schema with context: #{inspect(context)}"
      end
    end

    # Generate JSON schema
    json_schema = Instructor.JSONSchema.from_ecto_schema(TestSchema, %{status: "active"})

    # Pretty print the schema
    IO.puts("Generated JSON Schema:")
    IO.puts(Jason.encode!(Jason.decode!(json_schema), pretty: true))

    Instructor.chat_completion(
      model: "gpt-4o-mini",
      response_model: {TestSchema, %{status: "active"}},
      mode: :json,
      messages: [
        %{
          role: "user",
          content:
            "This is a structured output test, please reply with test data"
        }
      ]
    ) |> dbg()
  end
end
