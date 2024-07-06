defmodule Instructor.Adapters.Llamacpp do
  @moduledoc """
  Runs against the llama.cpp server. To be clear this calls the llamacpp specific
  endpoints, not the open-ai compliant ones.

  You can read more about it here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server
  """
  alias Instructor.JSONSchema
  alias Instructor.GBNF

  @behaviour Instructor.Adapter

  @doc """
  Run a completion against the llama.cpp server, not the open-ai compliant one.
  This gives you more specific control over the grammar, and the ability to
  provide other parameters to the specific LLM invocation.

  You can read more about the parameters here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server

  ## Examples

    iex> Instructor.chat_completion(
    ...>   model: "mistral-7b-instruct",
    ...>   messages: [
    ...>     %{ role: "user", content: "Classify the following text: Hello I am a Nigerian prince and I would like to send you money!" },
    ...>   ],
    ...>   response_model: response_model,
    ...>   temperature: 0.5,
    ...> )
  """
  @impl true
  def chat_completion(prompt, params, _config \\ nil) do
    stream = Keyword.get(params, :stream, false)

    if stream do
      do_streaming_chat_completion(prompt)
    else
      do_chat_completion(prompt)
    end
  end

  @impl true
  def prompt(params) do
    {response_model, _} = Keyword.pop!(params, :response_model)
    {messages, _} = Keyword.pop!(params, :messages)

    json_schema = JSONSchema.from_ecto_schema(response_model)
    grammar = GBNF.from_json_schema(json_schema)
    prompt = apply_chat_template(chat_template(), messages)

    %{
      grammar: grammar,
      prompt: prompt
    }
  end

  defp do_streaming_chat_completion(prompt) do
    pid = self()

    Stream.resource(
      fn ->
        Task.async(fn ->
          Req.post(url(),
            json: Map.put(prompt, :stream, true),
            receive_timeout: 60_000,
            into: fn {:data, data}, {req, resp} ->
              send(pid, data)
              {:cont, {req, resp}}
            end
          )

          send(pid, :done)
        end)
      end,
      fn acc ->
        receive do
          :done ->
            {:halt, acc}

          "data: " <> data ->
            data = Jason.decode!(data)
            {[data], acc}
        end
      end,
      fn acc -> acc end
    )
    |> Stream.map(fn %{"content" => chunk} ->
      to_openai_streaming_response(chunk)
    end)
  end

  defp to_openai_streaming_response(chunk) when is_binary(chunk) do
    %{
      "choices" => [
        %{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => chunk}}]}}
      ]
    }
  end

  defp do_chat_completion(prompt) do
    response =
      Req.post(url(),
        json: prompt,
        receive_timeout: 60_000
      )

    case response do
      {:ok, %{status: 200, body: %{"content" => params}}} ->
        {:ok, to_openai_response(params)}

      {:ok, %{status: status}} ->
        {:error, "Unexpected HTTP response code: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp to_openai_response(params) do
    %{
      "choices" => [
        %{
          "message" => %{
            "tool_calls" => [
              %{"id" => "schema", "function" => %{"name" => "schema", "arguments" => params}}
            ]
          }
        }
      ]
    }
  end

  defp apply_chat_template(:mistral_instruct, messages) do
    prompt =
      messages
      |> Enum.map_join("\n\n", fn
        %{role: "assistant", content: content} -> "#{content} </s>"
        %{content: content} -> "[INST] #{content} [/INST]"
      end)

    "<s>#{prompt}"
  end

  defp apply_chat_template(:tiny_llama, messages) do
    prompt =
      messages
      |> Enum.map_join("\n\n", fn
        %{role: role, content: content} -> "<|#{role}|>\n#{content} </s>"
        %{content: content} -> "<|user|>\n#{content} </s>"
      end)

    "<s>#{prompt}"
  end

  defp url() do
    Keyword.get(config(), :url, "http://localhost:8080/completion")
  end

  defp chat_template() do
    Keyword.get(config(), :chat_template, :mistral_instruct)
  end

  defp config() do
    base_config = Application.get_env(:instructor, :llamacpp, [])

    default_config = [
      chat_template: :mistral_instruct,
      api_url: "http://localhost:8080/completion"
    ]

    Keyword.merge(default_config, base_config)
  end
end
