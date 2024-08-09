defmodule Instructor.Adapters.OpenAI do
  @moduledoc """
  Documentation for `Instructor.Adapters.OpenAI`.
  """
  @behaviour Instructor.Adapter

  @impl true
  def chat_completion(params, config) do
    config = if config, do: config, else: config()

    # Peel off instructor only parameters
    {_, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :max_retries)
    {_, params} = Keyword.pop(params, :mode)
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
            Keyword.merge(options, [
              auth_header(config),
              json: params,
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
  end

  defp do_chat_completion(params, config) do
    options = Keyword.merge(http_options(config), [auth_header(config), json: params])

    case Req.post(url(config), options) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, "Unexpected HTTP response code: #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

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

  defp config() do
    base_config = Application.get_env(:instructor, :openai, [])

    default_config = [
      api_url: "https://api.openai.com",
      api_path: "/v1/chat/completions",
      auth_mode: :bearer,
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
