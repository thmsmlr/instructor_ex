defmodule Instructor.Validator do
  @moduledoc """
  By default you'll get whatever OpenAI returns.
  This behavior provides a hook for you to critique the response using standard ecto changesets validations.
  This can be used in conjuction with the `:max_retries` parameter to `Instructor.chat_completion/1` to retry the completion until it passes your validation.

  ## Examples

    defmodule Instructor.Demos.SpamPrediction do
      use Ecto.Schema

      @primary_key false
      schema "spam_prediction" do
          field :class, :string
          field :score, :float
      end

      @impl true
      def validate_changeset(changeset) do
          changeset
          |> validate_number(:score, less_than_or_equal_to: 1.0)
      end
    end

    iex> Instructor.chat_completion(%{
    ...>   model: "gpt-3.5-turbo",
    ...>   response_model: Instructor.Demos.SpamPrediction,
    ...>   max_retries: 1,
    ...>   messages: [
    ...>     %{
    ...>       role: "user",
    ...>       content: "Classify the following text: Hello, I am a Nigerian prince and I would like to give you $1,000,000."
    ...>     }
    ...> })
    {:error, %Ecto.Changeset{
        action: nil,
        changes: %{},
        errors: [
            score: {"is invalid", [validation: :number, validation_opts: [less_than_or_equal_to: 1.0]]}
        ],
        data: %Instructor.Demos.SpamPrediction{
            class: nil,
            score: nil
        },
        valid?: false
    }}
  """
  @callback validate_changeset(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  @callback validate_changeset(Ecto.Changeset.t(), Map.t()) :: Ecto.Changeset.t()
  @optional_callbacks [
    validate_changeset: 1,
    validate_changeset: 2
  ]

  defmacro __using__(_) do
    quote do
      @behaviour Instructor.Validator
    end
  end
end
