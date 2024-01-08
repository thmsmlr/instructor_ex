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

  defguardp is_ecto_schema(mod) when is_atom(mod)

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
    params =
      params
      |> Keyword.put_new(:max_retries, 0)
      |> Keyword.put_new(:mode, :tools)

    is_stream = Keyword.get(params, :stream, false)

    if is_stream do
      do_streaming_chat_completion(params)
    else
      do_chat_completion(params)
    end
  end

  def cast_all({data, types}, params) do
    fields = Map.keys(types)

    {data, types}
    |> Ecto.Changeset.cast(params, fields)
    |> Ecto.Changeset.validate_required(fields)
  end

  def cast_all(schema, params) do
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
          |> Ecto.Changeset.cast_embed(field, with: &cast_all/2)
      end

    changeset =
      for field <- associated_fields, reduce: changeset do
        changeset ->
          changeset
          |> Ecto.Changeset.cast_assoc(field, with: &cast_all/2)
      end

    changeset
  end

  defp do_streaming_chat_completion(params) do
    response_model =
      case Keyword.fetch!(params, :response_model) do
        {:array, x} -> x
      end

    wrapped_model = %{
      values:
        {:parameterized, Ecto.Embedded,
         %Ecto.Embedded{cardinality: :many, related: response_model}}
    }

    validation_context = Keyword.get(params, :validation_context, %{})
    mode = Keyword.get(params, :mode, :tools)

    params = params_for_tool(mode, wrapped_model, params)

    adapter().chat_completion(params)
    |> Stream.map(fn
      %{
        "choices" => [%{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => chunk}}]}}]
      } ->
        chunk

      %{"choices" => [%{"finish_reason" => "stop"}]} ->
        ""
    end)
    |> Jaxon.Stream.from_enumerable()
    |> Jaxon.Stream.query([:root, "values", :all])
    |> Stream.map(fn params ->
      model =
        if is_ecto_schema(response_model) do
          response_model.__struct__()
        else
          {%{}, response_model}
        end

      with changeset <- cast_all(model, params),
           {:validation, %Ecto.Changeset{valid?: true} = changeset} <-
             {:validation, call_validate(response_model, changeset, validation_context)} do
        {:ok, changeset |> Ecto.Changeset.apply_changes()}
      else
        {:validation, changeset} -> {:error, changeset}
        {:error, reason} -> {:error, reason}
        e -> {:error, e}
      end
    end)
  end

  defp do_chat_completion(params) do
    response_model = Keyword.fetch!(params, :response_model)
    validation_context = Keyword.get(params, :validation_context, %{})
    max_retries = Keyword.get(params, :max_retries)
    mode = Keyword.get(params, :mode, :tools)
    params = params_for_tool(mode, response_model, params)

    model =
      if is_ecto_schema(response_model) do
        response_model.__struct__()
      else
        {%{}, response_model}
      end

    with {:llm, {:ok, response}} <- {:llm, adapter().chat_completion(params)},
         {:valid_json, {:ok, params}} <- {:valid_json, parse_response_for_mode(mode, response)},
         changeset <- cast_all(model, params),
         {:validation, %Ecto.Changeset{valid?: true} = changeset, _response} <-
           {:validation, call_validate(response_model, changeset, validation_context), response} do
      {:ok, changeset |> Ecto.Changeset.apply_changes()}
    else
      {:llm, {:error, error}} ->
        {:error, "LLM Adapter Error: #{inspect(error)}"}

      {:valid_json, {:error, error}} ->
        {:error, "Invalid JSON returned from LLM: #{inspect(error)}"}

      {:validation, changeset, response} ->
        if max_retries > 0 do
          errors = Instructor.ErrorFormatter.format_errors(changeset)
          Logger.debug("Retrying LLM call for #{inspect(response_model)}...", errors: errors)

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

  defp echo_response(%{
         choices: [
           %{
             "message" =>
               %{
                 "tool_calls" => [
                   %{"id" => tool_call_id, "function" => %{"name" => name, "arguments" => args}} =
                     function
                 ]
               } = message
           }
         ]
       }) do
    [
      Map.put(message, "content", function |> Jason.encode!())
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end),
      %{
        role: "tool",
        tool_call_id: tool_call_id,
        name: name,
        content: args
      }
    ]
  end

  defp params_for_tool(:tools, response_model, params) do
    json_schema = JSONSchema.from_ecto_schema(response_model)
    title = JSONSchema.title_for(response_model) |> sanitize()

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

  defp sanitize(title),
    do: title |> String.replace("_", "-") |> String.replace("?", "") |> String.replace(".", "-")

  defp call_validate(response_model, changeset, context) do
    cond do
      not is_ecto_schema(response_model) ->
        changeset

      function_exported?(response_model, :validate_changeset, 1) ->
        response_model.validate_changeset(changeset)

      function_exported?(response_model, :validate_changeset, 2) ->
        response_model.validate_changeset(changeset, context)

      true ->
        changeset
    end
  end

  defp adapter() do
    Application.get_env(:instructor, :adapter, Instructor.Adapters.OpenAI)
  end
end
