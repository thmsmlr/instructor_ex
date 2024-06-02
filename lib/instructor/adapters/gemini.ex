defmodule Instructor.Adapters.Gemini do
  @moduledoc """
  Google Gemini adapter

  ## Resources

  - [Tutorial: Getting Started with the Gemini API](https://ai.google.dev/gemini-api/docs/get-started/tutorial?lang=rest)
  - [Gemini API Overview](https://ai.google.dev/gemini-api/docs/api-overview)
  - [Gemini REST API Reference](https://ai.google.dev/api/rest)
  """
  alias Instructor.JSONSchema

  @behaviour Instructor.Adapter

  def gemini_req,
    do:
      Req.new()
      |> Req.Request.register_options([:rpc_function])
      |> Req.Request.append_request_steps(
        append_rpc_function: fn request ->
          rpc_function = request.options[:rpc_function]

          if rpc_function do
            update_in(request.url.path, fn
              nil -> nil
              path -> path <> inspect(rpc_function)
            end)
          else
            request
          end
        end
      )

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
  def chat_completion(params, config \\ nil) do
    config = if config, do: config, else: config()

    {model_config_params, params} =
      Keyword.split(params, [:top_k, :top_p, :max_tokens, :temperature, :n, :stop])

    generationConfig =
      model_config_params
      |> Enum.into(%{}, fn
        {:stop, stops} ->
          {"stopSequences", stops}

        {:n, n} ->
          {"candidateCount", n}

        {:max_tokens, max_tokens} ->
          {"maxOutputTokens", max_tokens}

        {other_key, value} ->
          {Atom.to_string(other_key) |> snake_to_camel(), value}
      end)

    {response_model, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :adapter)
    {_, params} = Keyword.pop(params, :response_format)
    {max_retries, params} = Keyword.pop(params, :max_retries)
    {mode, params} = Keyword.pop(params, :mode, :json)
    {messages, params} = Keyword.pop!(params, :messages)
    messages = to_gemini_messages(messages)
    params = Keyword.put(params, :contents, messages)

    generationConfig =
      if mode == :json do
        Map.merge(generationConfig, %{
          "responseMimeType" => "application/json",
          "responseSchema" => JSONSchema.from_ecto_schema(response_model)
        })
      else
        generationConfig
      end

    Keyword.put(params, :generationConfig, generationConfig)

    stream = Keyword.get(params, :stream, false)
    params = Enum.into(params, %{})

    if stream do
      do_streaming_chat_completion(params, config)
    else
      do_chat_completion(params, config)
    end
  end

  defp do_streaming_chat_completion(params, config) do
    pid = self()
    options = http_options(config)

    Stream.resource(
      fn ->
        Task.async(fn ->
          options =
            Keyword.merge(options,
              json: params,
              auth: {:bearer, api_key(config)},
              into: fn {:data, data}, {req, resp} ->
                chunks =
                  data
                  |> String.split("\n")
                  |> Enum.filter(fn line ->
                    String.starts_with?(line, "data: {")
                  end)
                  |> Enum.map(fn line ->
                    line
                    |> String.replace_prefix("data: ", "")
                    |> Jason.decode!()
                  end)

                for chunk <- chunks do
                  send(pid, chunk)
                end

                {:cont, {req, resp}}
              end
            )

          Req.post!(url(config), options)
          send(pid, :done)
        end)
      end,
      fn task ->
        receive do
          :done ->
            {:halt, task}

          data ->
            {[data], task}
        after
          15_000 ->
            {:halt, task}
        end
      end,
      fn task -> Task.await(task) end
    )
  end

  defp to_gemini_messages(messages) do
    messages
    |> Enum.map(fn %{role: role, content: content} ->
      role = if role == "system", do: "model", else: role
      %{role: role, parts: [%{text: content}]}
    end)
  end

  defp to_openai_streaming_response(chunk) when is_binary(chunk) do
    %{
      "choices" => [
        %{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => chunk}}]}}
      ]
    }
  end

  defp do_chat_completion(params, config) do
    {model, params} = Map.pop!(params, :model)

    response =
      Req.merge(gemini_req(), http_options(config))
      |> Req.post!(
        url: url(config),
        path_params: [model: model, api_version: api_version(config)],
        headers: %{"x-goog-api-key" => api_key(config)},
        json: params,
        rpc_function: :generateContent
      )

    case response do
      %{
        status: 200,
        body: %{
          "candidates" => [
            %{
              "content" => %{
                "parts" => [
                  %{
                    "text" => params
                  }
                ]
              }
            }
          ]
        }
      } ->
        {:ok, to_openai_response(params)}

      %{
        status: 400,
        body: %{
          "error" => %{
            "code" => 400,
            "message" => message
          }
        }
      } ->
        {:error, message}

      _ ->
        {:error, "Unknown error occurred"}
    end
    |> dbg()
  end

  defp to_openai_response(<<"```json", _rest::binary>> = params) do
    params =
      params
      |> String.trim_leading("```json\n")
      |> String.trim_trailing("\n```")

    to_openai_response(params)
  end

  defp to_openai_response(params) do
    %{"choices" => [%{"message" => %{"content" => params}}]}
  end

  def snake_to_camel(snake_case_string) do
    snake_case_string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn {word, index} ->
      if index == 0 do
        String.downcase(word)
      else
        String.capitalize(word)
      end
    end)
    |> Enum.join("")
  end

  defp url(config), do: api_url(config) <> ":api_version/:model"
  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_key(config), do: Keyword.fetch!(config, :api_key)
  defp api_version(config), do: Keyword.fetch!(config, :api_version)
  defp http_options(config), do: Keyword.fetch!(config, :http_options)

  defp config() do
    base_config = Application.get_env(:instructor, :gemini, [])

    default_config = [
      api_version: :v1,
      api_url: "https://generativelanguage.googleapis.com/",
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
