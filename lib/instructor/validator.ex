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

    iex> Instructor.chat_completion(
    ...>   model: "gpt-3.5-turbo",
    ...>   response_model: Instructor.Demos.SpamPrediction,
    ...>   max_retries: 1,
    ...>   messages: [
    ...>     %{
    ...>       role: "user",
    ...>       content: "Classify the following text: Hello, I am a Nigerian prince and I would like to give you $1,000,000."
    ...>     }
    ...>   ])
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

      import Instructor.Validator
    end
  end

  defmodule Validation do
    use Ecto.Schema

    @doc """
    Validate if an attribute is correct and if not, return an error message
    """
    @primary_key false
    embedded_schema do
      field(:valid?, :boolean)
      field(:reason, :string)
    end
  end

  @doc """
  Validate a changeset field using a language model

  ## Example

    defmodule QuestionAnswer do
      use Ecto.Schema

      @primary_key false
      embedded_schema do
          field :question, :string
          field :answer, :string
      end

      @impl true
      def validate_changeset(changeset) do
          changeset
          |> validate_with_llm(:answer, "do not say anything objectionable")
      end
    end
  """
  def validate_with_llm(changeset, field, statement, opts \\ []) do
    Ecto.Changeset.validate_change(changeset, field, fn field, value ->
      {:ok, response, _usage} =
        Instructor.chat_completion(
          model: Keyword.get(opts, :model, "gpt-3.5-turbo"),
          temperature: Keyword.get(opts, :temperature, 0),
          response_model: Validation,
          messages: [
            %{
              role: "system",
              content: """
              You are a world class validation model. Capable to determine if the following value is valid for the statement, if it is not, explain why.
              """
            },
            %{
              role: "user",
              content: "Does `#{value}` follow the rules: #{statement}"
            }
          ]
        )

      case response do
        %Validation{valid?: true} ->
          []

        %Validation{reason: reason} ->
          [
            {field, "is invalid, #{reason}"}
          ]
      end
    end)
  end
end
