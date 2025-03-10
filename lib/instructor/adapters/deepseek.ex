defmodule Instructor.Adapters.DeepSeek do
  @moduledoc """
  DeepSeek Adapter for Instructor.

  ## Configuration

  ```elixir
  config :instructor, adapter: Instructor.Adapters.DeepSeek, deepseek: [
    api_key: "your_api_key" # Will use DEEPSEEK_API_KEY environment variable if not provided
  ]
  ```

  or at runtime:

  ```elixir
  Instructor.chat_completion(..., [
    adapter: Instructor.Adapters.DeepSeek,
    api_key: "your_api_key" # Will use DEEPSEEK_API_KEY environment variable if not provided
  ])
  ```

  To get an DeepSeek API key, see [DeepSeek](https://platform.deepseek.com/api_keys).
  """

  @behaviour Instructor.Adapter
  alias Instructor.Adapters
  alias Instructor.SSEStreamParser

  @supported_modes [:json_schema]

  @impl true
  def chat_completion(params, user_config \\ nil) do
    config = config(user_config)

    # Peel off instructor only parameters
    {_, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :max_retries)
    {mode, params} = Keyword.pop(params, :mode)
    {response_format, params} = Keyword.pop(params, :response_format)
    stream = Keyword.get(params, :stream, false)
    params = Enum.into(params, %{})

    if mode not in @supported_modes do
      raise "Unsupported DeepSeek mode #{mode}. Supported modes: #{inspect(@supported_modes)}"
    end

    params =
      if mode == :json_schema do
        Map.put(params, :response_format, %{type: "json_object"})
      else
        if response_format do
          Map.put(params, :response_format, response_format)
        else
          params
        end
      end

    if stream do
      do_streaming_chat_completion(mode, params, config)
    else
      do_chat_completion(mode, params, config)
    end
  end

  defp do_chat_completion(mode, params, config) do
    response =
      Req.new()
      |> Req.post(
        url: url(config),
        headers: %{"Authorization" => "Bearer " <> api_key(config)},
        json: params
      )

    with {:ok, %Req.Response{status: 200, body: body} = response} <- response,
         {:ok, body} <- parse_response_for_mode(mode, body) do
      {:ok, response, body}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Unexpected HTTP response code: #{status}\n#{inspect(body)}"}

      e ->
        e
    end
  end

  defp do_streaming_chat_completion(mode, params, config) do
    pid = self()

    Stream.resource(
      fn ->
        Task.async(fn ->
          options = [
            url: url(config),
            headers: %{"Authorization" => "Bearer " <> api_key(config)},
            json: params,
            into: fn {:data, data}, {req, resp} ->
              send(pid, data)
              {:cont, {req, resp}}
            end
          ]

          Req.post!(options)
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

  defp parse_response_for_mode(:json_schema, %{
         "choices" => [%{"message" => %{"content" => text}}]
       }) do
    Jason.decode(text)
  end

  defp parse_stream_chunk_for_mode(:json_schema, %{
         "choices" => [%{"delta" => %{"content" => chunk}}]
       }) do
    chunk
  end

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI

  defp url(config), do: api_url(config) <> "/chat/completions"
  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_key(config), do: Keyword.fetch!(config, :api_key)

  defp config(nil), do: config(Application.get_env(:instructor, :deepseek, []))

  defp config(base_config) do
    default_config = [
      api_url: "https://api.deepseek.com",
      api_key: System.get_env("DEEPSEEK_API_KEY"),
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
