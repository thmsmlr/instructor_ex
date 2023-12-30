defmodule Instructor do
  require Logger

  alias Instructor.JSONSchema

  @external_resource "README.md"

  [_, readme_docs, _] =
    "README.md"
    |> File.read!()
    |> String.split("<!-- Docs -->")

  @moduledoc """
  #{readme_docs}
  """

  @doc """
  Create a new chat completion for the provided messages and parameters.

  The parameters are passed directly to the LLM adapter.
  By default they shadow the OpenAI API parameters.
  For more information on the parameters, see the [OpenAI API docs](https://platform.openai.com/docs/api-reference/chat-completions/create).

  Additionally, the following parameters are supported:

    * `:response_model` - The Ecto schema to validate the response against.
    * `:max_retries` - The maximum number of times to retry the LLM call if it fails, or does not pass validations.
                       (defaults to `0`)

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

    params =
      params
      |> Keyword.put(:validate, validate)
      |> Keyword.put_new(:max_retries, 0)
      |> Keyword.put_new(:mode, :tools)

    do_chat_completion(params)
  end

  defp do_chat_completion(params) do
    response_model = params[:response_model]
    validate = params[:validate]
    max_retries = params[:max_retries]
    mode = Keyword.get(params, :mode, :tools)
    params = params_for_tool(mode, params)

    with {:llm, {:ok, response}} <- {:llm, adapter().chat_completion(params)},
         {:valid_json, {:ok, params}} <- {:valid_json, parse_response_for_mode(mode, response)},
         changeset <- to_changeset(response_model.__struct__(), params),
         {:validation, %Ecto.Changeset{valid?: true} = changeset, _response} <-
           {:validation, validate.(changeset), response} do
      {:ok, changeset |> Ecto.Changeset.apply_changes()}
    else
      {:llm, {:error, error}} ->
        {:error, "LLM Adapter Error: #{inspect(error)}"}

      {:valid_json, {:error, error}} ->
        {:error, "Invalid JSON returned from LLM: #{inspect(error)}"}

      {:validation, changeset, response} ->
        if max_retries > 0 do
          errors = format_errors(changeset)
          Logger.debug("Retrying LLM call for #{response_model}...", errors: errors)

          params =
            params
            |> Keyword.put(:max_retries, max_retries - 1)
            |> Keyword.update(:messages, [], fn messages ->
              messages ++
                echo_response(response) ++
                [
                  %{
                    role: "system",
                    content: """
                    The response did not pass validation. Please try again and fix the following validation errors:\n

                    #{errors}
                    """
                  }
                ]
            end)

          do_chat_completion(params)
        else
          {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}

      e ->
        {:error, e}
    end
  end

  defp parse_response_for_mode(:tools, %{
         choices: [
           %{
             "message" => %{
               "tool_calls" => [%{"function" => %{"arguments" => args}}]
             }
           }
         ]
       }) do
    Jason.decode(args)
  end

  defp echo_response(%{choices: [%{"message" => %{"tool_calls" => [function]}}]}) do
    [
      %{
        role: "assistant",
        content: Jason.encode!(function)
      }
    ]
  end

  #
  # Though technically correct for the tools api, seems to yield worse results.
  # Leaving here to investigate further later.
  # defp echo_response(%{
  #        choices: [
  #          %{
  #            "message" =>
  #              %{
  #                "tool_calls" => [
  #                  %{"id" => tool_call_id, "function" => %{"name" => name, "arguments" => args}} =
  #                    function
  #                ]
  #              } = message
  #          }
  #        ]
  #      }) do
  #   [
  #     Map.put(message, "content", function |> Jason.encode!()),
  #     %{
  #       role: "tool",
  #       tool_call_id: tool_call_id,
  #       name: name,
  #       content: args
  #     }
  #   ]
  # end

  defp params_for_tool(:tools, params) do
    response_model = Keyword.fetch!(params, :response_model)
    json_schema = JSONSchema.from_ecto_schema(response_model)
    title = JSONSchema.title_for(response_model)

    params =
      params
      |> Keyword.update(:messages, [], fn messages ->
        sys_message = %{
          role: "system",
          content: """
          As a genius expert, your task is to understand the content and provide the parsed objects in json that match the following json_schema:\n

          #{json_schema}
          """
        }

        [sys_message | messages]
      end)
      |> Keyword.put(:tools, [
        %{
          type: "function",
          function: %{
            "description" =>
              "Correctly extracted `#{title}` with all the required parameters with correct types",
            "name" => title,
            "parameters" => json_schema |> Jason.decode!()
          }
        }
      ])
      |> Keyword.put(:tool_choice, %{
        type: "function",
        function: %{name: title}
      })

    params
  end

  defp to_changeset(schema, params) do
    response_model = schema.__struct__
    fields = response_model.__schema__(:fields) |> MapSet.new()
    embedded_fields = response_model.__schema__(:embeds) |> MapSet.new()
    associated_fields = response_model.__schema__(:associations) |> MapSet.new()

    fields =
      fields
      |> MapSet.difference(embedded_fields)
      |> MapSet.difference(associated_fields)

    changeset =
      schema
      |> Ecto.Changeset.cast(params, fields |> MapSet.to_list())

    changeset =
      for field <- embedded_fields, reduce: changeset do
        changeset ->
          changeset
          |> Ecto.Changeset.cast_embed(field, with: &to_changeset/2)
      end

    changeset =
      for field <- associated_fields, reduce: changeset do
        changeset ->
          changeset
          |> Ecto.Changeset.cast_assoc(field, with: &to_changeset/2)
      end

    changeset
  end

  defp format_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn _changeset, _field, {msg, opts} ->
        msg =
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)

        "#{msg}"
      end)
      |> Map.values()
      |> List.flatten()

    Enum.join(errors, ", and ")
  end

  defp adapter() do
    Application.get_env(:instructor, :adapter, Instructor.Adapters.OpenAI)
  end
end
