defmodule Instructor do
  @moduledoc """
  Instructor is a library for structured prompting of LLMs.

  See Instructor.chat_completion/1 for more information on how to use it.

  By default we use the OpenAI adapter, but you can configure your own adapter by setting the `:adapter` config value.

  ## Configuration

    Instructor can be configured in your `config.exs` file:

        config :instructor, adapter: Instructor.Adapters.OpenAI
        config :openai, api_key: "sk-........"
        config :openai, http_options: [recv_timeout: 10 * 60 * 1000]

    Other adapters are Instructor.Adapters.Llamacpp
  """

  @doc """
  Create a new chat completion for the provided messages and parameters.

  The parameters are passed directly to the LLM adapter.
  By default they shadow the OpenAI API parameters.
  For more information on the parameters, see the [OpenAI API docs](https://platform.openai.com/docs/api-reference/chat-completions/create).

  Additionally, the following parameters are supported:

    * `:response_model` - The Ecto schema to validate the response against.

  ## Examples

    iex> Instructor.chat_completion(%{
    ...>   model: "gpt-3.5-turbo",
    ...>   response_model: Instructor.Demos.SpamPrediction,
    ...>   messages: [
    ...>     %{
    ...>       role: "user",
    ...>       content: "Classify the following text: Hello, I am a Nigerian prince and I would like to give you $1,000,000."
    ...>     }
    ...> })
    {:ok,
        %Instructor.Demos.SpamPrediction{
            class: :spam
            score: 0.999
        }}
  """
  @spec chat_completion(Keyword.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()} | {:error, String.t()}
  def chat_completion(params) do
    response_model = Keyword.get(params, :response_model)

    validate =
      if function_exported?(response_model, :validate_changeset, 1) do
        &response_model.validate_changeset/1
      else
        fn x -> x end
      end

    with {:llm, {:ok, params}} <- {:llm, adapter().chat_completion(params)},
         {:valid_json, {:ok, params}} <- {:valid_json, Jason.decode(params)},
         changeset <- to_changeset(response_model, params),
         {:validation, %Ecto.Changeset{valid?: true} = changeset} <-
           {:validation, validate.(changeset)} do
      {:ok, changeset |> Ecto.Changeset.apply_changes()}
    else
      {:llm, {:error, error}} ->
        {:error, "LLM Adapter Error: #{inspect(error)}"}

      {:valid_json, {:error, error}} ->
        {:error, "Invalid JSON returned from LLM: #{inspect(error)}"}

      {:validation, changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, "Unknown error"}
    end
  end

  defp to_changeset(schema, params) do
    schema.__struct__()
    |> Ecto.Changeset.cast(params, schema.__schema__(:fields))
  end

  defp adapter() do
    Application.get_env(:instructor, :adapter, Instructor.Adapters.OpenAI)
  end
end
