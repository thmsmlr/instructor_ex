defmodule Instructor.Adapters.OpenAI do
  @moduledoc """
  Documentation for `Instructor.Adapters.OpenAI`.
  """
  @behaviour Instructor.Adapter
  @supported_modes [:tools, :json, :md_json, :json_schema]

  alias Instructor.JSONSchema
  alias Instructor.SSEStreamParser

  @impl true
  def chat_completion(params, user_config \\ nil) do
    config = config(user_config)

    # Peel off instructor only parameters
    {_, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :max_retries)
    {mode, params} = Keyword.pop(params, :mode)
    stream = Keyword.get(params, :stream, false)
    params = Enum.into(params, %{})

    if mode not in @supported_modes do
      raise "Unsupported OpenAI mode #{mode}. Supported modes: #{inspect(@supported_modes)}"
    end

    params =
      case params do
        # OpenAI's json_schema mode doesn't support format or pattern attributes
        %{"response_format" => %{"json_schema" => %{"schema" => _schema}}} ->
          update_in(params, [:response_format, :json_schema, :schema], fn schema ->
            JSONSchema.traverse_and_update(schema, fn
              %{"type" => _} = x when is_map_key(x, "format") or is_map_key(x, "pattern") ->
                Map.drop(x, ["format", "pattern"])

              x ->
                x
            end)
          end)

        _ ->
          params
      end

    if stream do
      do_streaming_chat_completion(mode, params, config)
    else
      do_chat_completion(mode, params, config)
    end
  end

  @impl true
  def reask_messages(raw_response, params, _config) do
    reask_messages_for_mode(params[:mode], raw_response)
  end

  defp reask_messages_for_mode(:tools, %{
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

  defp reask_messages_for_mode(_mode, _raw_response) do
    []
  end

  defp do_streaming_chat_completion(mode, params, config) do
    pid = self()
    options = http_options(config)

    Stream.resource(
      fn ->
        Task.async(fn ->
          options =
            Keyword.merge(options, [
              auth_header(config),
              json: params,
              into: fn {:data, data}, {req, resp} ->
                send(pid, data)
                {:cont, {req, resp}}
              end
            ])

          Req.post(url(config), options)
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
    |> SSEStreamParser.parse()
    |> Stream.map(fn chunk -> parse_stream_chunk_for_mode(mode, chunk) end)
  end

  defp do_chat_completion(mode, params, config) do
    options = Keyword.merge(http_options(config), [auth_header(config), json: params])

    with {:ok, %Req.Response{status: 200, body: body} = response} <-
           Req.post(url(config), options),
         {:ok, content} <- parse_response_for_mode(mode, body) do
      {:ok, response, content}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Unexpected HTTP response code: #{status}\n#{inspect(body)}"}

      e ->
        e
    end
  end

  defp parse_response_for_mode(:tools, %{
         "choices" => [
           %{"message" => %{"tool_calls" => [%{"function" => %{"arguments" => args}}]}}
         ]
       }),
       do: Jason.decode(args)

  defp parse_response_for_mode(:md_json, %{"choices" => [%{"message" => %{"content" => content}}]}),
       do: Jason.decode(content)

  defp parse_response_for_mode(:json, %{"choices" => [%{"message" => %{"content" => content}}]}),
    do: Jason.decode(content)

  defp parse_response_for_mode(:json_schema, %{
         "choices" => [%{"message" => %{"content" => content}}]
       }),
       do: Jason.decode(content)

  defp parse_response_for_mode(mode, response) do
    {:error, "Unsupported OpenAI mode #{mode} with response #{inspect(response)}"}
  end

  defp parse_stream_chunk_for_mode(:md_json, %{"choices" => [%{"delta" => %{"content" => chunk}}]}),
       do: chunk

  defp parse_stream_chunk_for_mode(:json, %{"choices" => [%{"delta" => %{"content" => chunk}}]}),
    do: chunk

  defp parse_stream_chunk_for_mode(:json_schema, %{
         "choices" => [%{"delta" => %{"content" => chunk}}]
       }),
       do: chunk

  defp parse_stream_chunk_for_mode(:tools, %{
         "choices" => [
           %{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => chunk}}]}}
         ]
       }),
       do: chunk

  defp parse_stream_chunk_for_mode(:tools, %{
         "choices" => [
           %{"delta" => delta}
         ]
       }) do
    case delta do
      nil -> ""
      %{} -> ""
      %{"content" => chunk} -> chunk
    end
  end

  defp parse_stream_chunk_for_mode(_, %{"choices" => [%{"finish_reason" => "stop"}]}), do: ""

  defp url(config), do: api_url(config) <> api_path(config)
  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_path(config), do: Keyword.fetch!(config, :api_path)

  defp api_key(config) do
    case Keyword.fetch!(config, :api_key) do
      string when is_binary(string) -> string
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp auth_header(config) do
    case Keyword.fetch!(config, :auth_mode) do
      # https://learn.microsoft.com/en-us/azure/ai-services/openai/reference
      :api_key_header -> {:headers, %{"api-key" => api_key(config)}}
      _ -> {:auth, {:bearer, api_key(config)}}
    end
  end

  defp http_options(config), do: Keyword.fetch!(config, :http_options)

  defp config(nil), do: config(Application.get_env(:instructor, :openai, []))

  defp config(base_config) do
    default_config = [
      api_url: "https://api.openai.com",
      api_path: "/v1/chat/completions",
      auth_mode: :bearer,
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
