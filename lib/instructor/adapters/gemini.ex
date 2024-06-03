defmodule Instructor.Adapters.Gemini do
  @moduledoc """
  Google Gemini adapter

  ## Configuration

  Accepts the following configuration options either from your `Application` environment or as a param:

  - `:api_version`: Gemini has a `v1` and a `v1beta` API. Defaults to `v1beta`. The `v1` API does
     not support JSON mode, so if you use `v1` you cannot use `mode: :json` (which is the default mode).
  - `:api_url`: Base URL for the Gemini API. Defaults to `"https://generativelanguage.googleapis.com/"`

  Additionally, the Gemini API accepts a `GenerationConfig` to change the model's behaviors. This adapter
  will perform the following transformations from OpenAI styled arguemnts
  (see https://ai.google.dev/api/rest/v1beta/GenerationConfig for Google's API):

  - `:stop` -> `stopSequences`
  - `:n` -> `candidateCount`
  -  :max_tokens` -> `maxOutputToken`
  - `:top_k` -> `topK`
  - `:top_p` -> `topP`

  ## Resources

  - [Tutorial: Getting Started with the Gemini API](https://ai.google.dev/gemini-api/docs/get-started/tutorial?lang=rest)
  - [Gemini API Overview](https://ai.google.dev/gemini-api/docs/api-overview)
  - [Gemini REST API Reference](https://ai.google.dev/api/rest)
  - [Gemini API: JSON Mode Quickstart with REST](https://github.com/google-gemini/cookbook/blob/main/quickstarts/rest/JSON_mode_REST.ipynb)
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
  Run a completion against Google's Gemini API

  Accepts OpenAI API arguments and converts to Gemini Args to perform the completion.

  Defaults to JSON mode within the Gemini API
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

    {_response_model, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :adapter)
    {_, params} = Keyword.pop(params, :response_format)
    {_, params} = Keyword.pop(params, :max_retries)
    {mode, params} = Keyword.pop(params, :mode, :json)
    {messages, params} = Keyword.pop!(params, :messages)
    params = params ++ to_gemini_params(messages)

    generationConfig =
      if mode == :json do
        Map.merge(generationConfig, %{
          "responseMimeType" => "application/json"
          # This should work according to the docs but it didn't work initially when trying to add.
          # Also, the cookboox example doesn't use this config arg for JSON output, AND Instructor
          # already prepends the schema as a system instruction.
          # Docs are here:
          # "responseSchema" => JSONSchema.from_ecto_schema(response_model)
        })
      else
        generationConfig
      end

    params = Keyword.put(params, :generationConfig, generationConfig)

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

  defp to_gemini_params(messages) do
    {systemInstruction, contents} =
      messages
      |> Enum.reduce({%{role: "system", parts: []}, []}, fn
        %{role: "assistant", content: content}, {system_instructions, history} ->
          {system_instructions, [%{role: "model", parts: [%{text: content}]} | history]}

        %{role: "user", content: content}, {system_instructions, history} ->
          {system_instructions, [%{role: "user", parts: [%{text: content}]} | history]}

        %{role: "system", content: content}, {system_instructions, history} ->
          part = %{text: content}
          {Map.update!(system_instructions, :parts, fn parts -> [part | parts] end), history}
      end)

    systemInstruction = Map.update!(systemInstruction, :parts, &Enum.reverse/1)
    contents = Enum.reverse(contents)
    [systemInstruction: systemInstruction, contents: contents]
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
  end

  defp to_openai_response(<<"```json", _rest::binary>> = params) do
    params
    |> String.trim_leading("```json\n")
    |> String.trim_trailing("\n```")
    |> to_openai_response()
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
      api_version: :v1beta,
      api_url: "https://generativelanguage.googleapis.com/",
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
