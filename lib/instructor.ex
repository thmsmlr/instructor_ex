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

    * `:adapter` - The adapter to use for chat completion. (defaults to the configured adapter, which defaults to `Instructor.Adapters.OpenAI`)
    * `:response_model` - The Ecto schema to validate the response against, or a valid map of Ecto types (see [Schemaless Ecto](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-schemaless-changesets)).
    * `:stream` - Whether to stream the response or not. (defaults to `false`)
    * `:validation_context` - The validation context to use when validating the response. (defaults to `%{}`)
    * `:mode` - The mode to use when parsing the response, :tools, :json, :md_json (defaults to `:tools`), generally speaking you don't need to change this unless you are not using OpenAI.
    * `:max_retries` - The maximum number of times to retry the LLM call if it fails, or does not pass validations.
                       (defaults to `0`)

  ## Examples

      iex> Instructor.chat_completion(
      ...>   model: "gpt-3.5-turbo",
      ...>   response_model: Instructor.Demos.SpamPrediction,
      ...>   messages: [
      ...>     %{
      ...>       role: "user",
      ...>       content: "Classify the following text: Hello, I am a Nigerian prince and I would like to give you $1,000,000."
      ...>     }
      ...>   ])
      {:ok,
          %Instructor.Demos.SpamPrediction{
              class: :spam
              score: 0.999
          }}

  When you're using Instructor in Streaming Mode, instead of returning back a tuple, it will return back a stream that emits tuples.
  There are two main streaming modes available. array streaming and partial streaming.

  Partial streaming will emit the record multiple times until it's complete.

      iex> Instructor.chat_completion(
      ...>   model: "gpt-3.5-turbo",
      ...>   response_model: {:partial, %{name: :string, birth_date: :date}}
      ...>   messages: [
      ...>     %{
      ...>       role: "user",
      ...>       content: "Who is the first president of the United States?"
      ...>     }
      ...>   ]) |> Enum.to_list()
      [
        {:partial, %{name: "George Washington"}},
        {:partial, %{name: "George Washington", birth_date: ~D[1732-02-22]}},
        {:ok, %{name: "George Washington", birth_date: ~D[1732-02-22]}}
      ]

  Whereas with array streaming, you can ask the LLM to return multiple instances of your Ecto schema,
  and instructor will emit them one at a time as they arrive in complete form and validated.

      iex> Instructor.chat_completion(
      ...>   model: "gpt-3.5-turbo",
      ...>   response_model: {:array, %{name: :string, birth_date: :date}}
      ...>   messages: [
      ...>     %{
      ...>       role: "user",
      ...>       content: "Who are the first 5 presidents of the United States?"
      ...>     }
      ...>   ]) |> Enum.to_list()

      [
        {:ok, %{name: "George Washington", birth_date: ~D[1732-02-22]}},
        {:ok, %{name: "John Adams", birth_date: ~D[1735-10-30]}},
        {:ok, %{name: "Thomas Jefferson", birth_date: ~D[1743-04-13]}},
        {:ok, %{name: "James Madison", birth_date: ~D[1751-03-16]}},
        {:ok, %{name: "James Monroe", birth_date: ~D[1758-04-28]}}
      ]

  If there's a validation error, it will return an error tuple with the change set describing the errors.

      iex> Instructor.chat_completion(
      ...>   model: "gpt-3.5-turbo",
      ...>   response_model: Instructor.Demos.SpamPrediction,
      ...>   messages: [
      ...>     %{
      ...>       role: "user",
      ...>       content: "Classify the following text: Hello, I am a Nigerian prince and I would like to give you $1,000,000."
      ...>     }
      ...>   ])
      {:error,
          %Ecto.Changeset{
              changes: %{
                  class: "foobar",
                  score: -10.999
              },
              errors: [
                  class: {"is invalid", [type: :string, validation: :cast]}
              ],
              valid?: false
          }}
  """
  @spec chat_completion(Keyword.t(), any()) ::
          {:ok, Ecto.Schema.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, String.t()}
          | Stream.t()
  def chat_completion(params, config \\ nil) do
    params =
      params
      |> Keyword.put_new(:max_retries, 0)
      |> Keyword.put_new(:mode, :tools)

    is_stream = Keyword.get(params, :stream, false)
    response_model = Keyword.fetch!(params, :response_model)

    case {response_model, is_stream} do
      {{:partial, {:array, response_model}}, true} ->
        do_streaming_partial_array_chat_completion(response_model, params, config)

      {{:partial, response_model}, true} ->
        do_streaming_partial_chat_completion(response_model, params, config)

      {{:array, response_model}, true} ->
        do_streaming_array_chat_completion(response_model, params, config)

      {response_model, false} ->
        do_chat_completion(response_model, params, config)

      {_, true} ->
        raise """
        Streaming not supported for response_model: #{inspect(response_model)}.

        Make sure the response_model is a module that uses `Ecto.Schema` or is a valid Schemaless Ecto type definition.
        """
    end
  end

  @doc """
  Casts all the parameters in the params map to the types defined in the types map.
  This works both with Ecto Schemas and maps of Ecto types (see [Schemaless Ecto](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-schemaless-changesets)).

  ## Examples

  When using a full Ecto Schema

      iex> Instructor.cast_all(%{
      ...>   data: %Instructor.Demos.SpamPrediction{},
      ...>   types: %{
      ...>     class: :string,
      ...>     score: :float
      ...>   }
      ...> }, %{
      ...>   class: "spam",
      ...>   score: 0.999
      ...> })
      %Ecto.Changeset{
        action: nil,
        changes: %{
          class: "spam",
          score: 0.999
        },
        errors: [],
        data: %Instructor.Demos.SpamPrediction{
          class: :spam,
          score: 0.999
        },
        valid?: true
      }

  When using a map of Ecto types

      iex> Instructor.cast_all(%Instructor.Demo.SpamPrediction{}, %{
      ...>   class: "spam",
      ...>   score: 0.999
      ...> })
      %Ecto.Changeset{
        action: nil,
        changes: %{
          class: "spam",
          score: 0.999
        },
        errors: [],
        data: %{
          class: :spam,
          score: 0.999
        },
        valid?: true
      }

  and when using raw Ecto types,

      iex> Instructor.cast_all({%{},%{name: :string}, %{
      ...>   name: "George Washington"
      ...> })
      %Ecto.Changeset{
        action: nil,
        changes: %{
          name: "George Washington",
        },
        errors: [],
        data: %{
          name: "George Washington",
        },
        valid?: true
      }

  """
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

  @spec prepare_prompt(Keyword.t()) :: map()
  def prepare_prompt(params, config \\ nil) do
    response_model = Keyword.fetch!(params, :response_model)
    mode = Keyword.get(params, :mode, :tools)
    params = params_for_mode(mode, response_model, params)

    adapter(config).prompt(params)
  end

  @spec consume_response(any(), Keyword.t()) ::
          {:ok, map()} | {:error, String.t()} | {:error, Ecto.Changeset.t(), Keyword.t()}
  def consume_response(response, params) do
    validation_context = Keyword.get(params, :validation_context, %{})
    response_model = Keyword.fetch!(params, :response_model)
    mode = Keyword.get(params, :mode, :tools)

    model =
      if is_ecto_schema(response_model) do
        response_model.__struct__()
      else
        {%{}, response_model}
      end

    with {:valid_json, {:ok, params}} <- {:valid_json, parse_response_for_mode(mode, response)},
         changeset <- cast_all(model, params),
         {:validation, %Ecto.Changeset{valid?: true} = changeset, _response} <-
           {:validation, call_validate(response_model, changeset, validation_context), response} do
      {:ok, changeset |> Ecto.Changeset.apply_changes()}
    else
      {:valid_json, {:error, error}} ->
        {:error, "Invalid JSON returned from LLM: #{inspect(error)}"}

      {:validation, changeset, response} ->
        errors = Instructor.ErrorFormatter.format_errors(changeset)

        params =
          Keyword.update(params, :messages, [], fn messages ->
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

        {:error, changeset, params}
    end
  end

  defp do_streaming_partial_array_chat_completion(response_model, params, config) do
    wrapped_model = %{
      value:
        {:parameterized, Ecto.Embedded,
         %Ecto.Embedded{cardinality: :many, related: response_model}}
    }

    params = Keyword.put(params, :response_model, wrapped_model)
    validation_context = Keyword.get(params, :validation_context, %{})
    mode = Keyword.get(params, :mode, :tools)
    prompt = prepare_prompt(params, config)

    model =
      if is_ecto_schema(response_model) do
        response_model.__struct__()
      else
        {%{}, response_model}
      end

    adapter(config).chat_completion(prompt, params, config)
    |> Stream.map(&parse_stream_chunk_for_mode(mode, &1))
    |> Instructor.JSONStreamParser.parse()
    |> Stream.transform(
      fn -> {nil, []} end,
      # reducer
      fn
        %{"value" => []}, {last, acc} ->
          {[], {last, acc}}

        %{"value" => params_array}, {last, acc} ->
          acc =
            if length(params_array) == length(acc) + 2 do
              with changeset <- cast_all(model, Map.from_struct(last)),
                   {:validation, %Ecto.Changeset{valid?: true} = changeset} <-
                     {:validation, call_validate(response_model, changeset, validation_context)} do
                acc ++ [{:ok, changeset |> Ecto.Changeset.apply_changes()}]
              else
                {:validation, changeset} -> acc ++ [{:error, changeset}]
                {:error, reason} -> acc ++ [{:error, reason}]
                e -> acc ++ [{:error, e}]
              end
            else
              acc
            end

          params = List.last(params_array)
          last = model |> cast_all(params) |> Ecto.Changeset.apply_changes()
          {[acc ++ [{:partial, last}]], {last, acc}}

        %{}, acc ->
          {[], acc}
      end,
      # last, validate last entry, emit all
      fn {last, acc} ->
        acc =
          with changeset <- cast_all(model, Map.from_struct(last)),
               {:validation, %Ecto.Changeset{valid?: true} = changeset} <-
                 {:validation, call_validate(response_model, changeset, validation_context)} do
            acc ++ [{:ok, changeset |> Ecto.Changeset.apply_changes()}]
          else
            {:validation, changeset} -> acc ++ [{:error, changeset}]
            {:error, reason} -> acc ++ [{:error, reason}]
            e -> acc ++ [{:error, e}]
          end

        {[acc], nil}
      end,
      fn _acc -> nil end
    )
  end

  defp do_streaming_partial_chat_completion(response_model, params, config) do
    wrapped_model = %{
      value:
        {:parameterized, Ecto.Embedded,
         %Ecto.Embedded{cardinality: :one, related: response_model}}
    }

    params = Keyword.put(params, :response_model, wrapped_model)
    validation_context = Keyword.get(params, :validation_context, %{})
    mode = Keyword.get(params, :mode, :tools)
    prompt = prepare_prompt(params, config)

    adapter(config).chat_completion(prompt, params, config)
    |> Stream.map(&parse_stream_chunk_for_mode(mode, &1))
    |> Instructor.JSONStreamParser.parse()
    |> Stream.transform(
      fn -> nil end,
      # partial
      fn params, _acc ->
        params = Map.get(params, "value", %{})

        model =
          if is_ecto_schema(response_model) do
            response_model.__struct__()
          else
            {%{}, response_model}
          end

        changeset = cast_all(model, params)
        model = changeset |> Ecto.Changeset.apply_changes()
        {[{:partial, model}], changeset}
      end,
      # last
      fn changeset ->
        with {:validation, %Ecto.Changeset{valid?: true} = changeset} <-
               {:validation, call_validate(response_model, changeset, validation_context)} do
          model = changeset |> Ecto.Changeset.apply_changes()
          {[{:ok, model}], nil}
        else
          {:validation, changeset} -> [{:error, changeset}]
          {:error, reason} -> {:error, reason}
          e -> {:error, e}
        end
      end,
      fn _acc -> nil end
    )
  end

  defp do_streaming_array_chat_completion(response_model, params, config) do
    wrapped_model = %{
      value:
        {:parameterized, Ecto.Embedded,
         %Ecto.Embedded{cardinality: :many, related: response_model}}
    }

    params = Keyword.put(params, :response_model, wrapped_model)
    validation_context = Keyword.get(params, :validation_context, %{})
    mode = Keyword.get(params, :mode, :tools)

    prompt = prepare_prompt(params, config)

    adapter(config).chat_completion(prompt, params, config)
    |> Stream.map(&parse_stream_chunk_for_mode(mode, &1))
    |> Jaxon.Stream.from_enumerable()
    |> Jaxon.Stream.query([:root, "value", :all])
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

  defp do_chat_completion(response_model, params, config) do
    max_retries = Keyword.get(params, :max_retries)
    prompt = prepare_prompt(params, config)

    with {:llm, {:ok, response}} <-
           {:llm, adapter(config).chat_completion(prompt, params, config)},
         {:ok, result} <- consume_response(response, params) do
      {:ok, result}
    else
      {:llm, {:error, error}} ->
        {:error, "LLM Adapter Error: #{inspect(error)}"}

      {:error, changeset, new_params} ->
        if max_retries > 0 do
          errors = Instructor.ErrorFormatter.format_errors(changeset)

          Logger.debug("Retrying LLM call for #{inspect(response_model)}:\n\n #{inspect(errors)}",
            errors: errors
          )

          params = Keyword.put(new_params, :max_retries, max_retries - 1)

          do_chat_completion(response_model, params, config)
        else
          {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}

      e ->
        {:error, e}
    end
  end

  defp parse_response_for_mode(:md_json, %{"choices" => [%{"message" => %{"content" => content}}]}),
       do: Jason.decode(content)

  defp parse_response_for_mode(:json, %{"choices" => [%{"message" => %{"content" => content}}]}),
    do: Jason.decode(content)

  defp parse_response_for_mode(:tools, %{
         "choices" => [
           %{"message" => %{"tool_calls" => [%{"function" => %{"arguments" => args}}]}}
         ]
       }),
       do: Jason.decode(args)

  defp parse_stream_chunk_for_mode(:md_json, %{"choices" => [%{"delta" => %{"content" => chunk}}]}),
       do: chunk

  defp parse_stream_chunk_for_mode(:json, %{"choices" => [%{"delta" => %{"content" => chunk}}]}),
    do: chunk

  defp parse_stream_chunk_for_mode(:tools, %{
         "choices" => [
           %{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => chunk}}]}}
         ]
       }),
       do: chunk

  defp parse_stream_chunk_for_mode(_, %{"choices" => [%{"finish_reason" => "stop"}]}), do: ""

  defp echo_response(%{
         "choices" => [
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

  defp params_for_mode(mode, response_model, params) do
    json_schema = JSONSchema.from_ecto_schema(response_model)

    params =
      params
      |> Keyword.update(:messages, [], fn messages ->
        decoded_json_schema = Jason.decode!(json_schema)

        additional_definitions =
          if defs = decoded_json_schema["$defs"] do
            "\nHere are some more definitions to adhere too:\n" <> Jason.encode!(defs)
          else
            ""
          end

        sys_message = %{
          role: "system",
          content: """
          As a genius expert, your task is to understand the content and provide the parsed objects in json that match the following json_schema:\n
          #{json_schema}

          #{additional_definitions}
          """
        }

        case mode do
          :md_json ->
            [sys_message | messages] ++
              [
                %{
                  role: "assistant",
                  content: "Here is the perfectly correctly formatted JSON\n```json"
                }
              ]

          :json ->
            [sys_message | messages]

          :tools ->
            messages
        end
      end)

    case mode do
      :md_json ->
        params |> Keyword.put(:stop, "```")

      :json ->
        params
        |> Keyword.put(:response_format, %{
          type: "json_object"
        })

      :tools ->
        params
        |> Keyword.put(:tools, [
          %{
            type: "function",
            function: %{
              "description" =>
                "Correctly extracted `Schema` with all the required parameters with correct types",
              "name" => "Schema",
              "parameters" => json_schema |> Jason.decode!()
            }
          }
        ])
        |> Keyword.put(:tool_choice, %{
          type: "function",
          function: %{name: "Schema"}
        })
    end
  end

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

  defp adapter(%{adapter: adapter}) when is_atom(adapter), do: adapter
  defp adapter(_), do: Application.get_env(:instructor, :adapter, Instructor.Adapters.OpenAI)
end
