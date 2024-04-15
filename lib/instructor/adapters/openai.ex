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
    {inspect_request?, params} = Keyword.pop(params, :inspect_request?)
    {inspect_response?, params} = Keyword.pop(params, :inspect_response?)
    stream = Keyword.get(params, :stream, false)
    params = Enum.into(params, %{})

    if stream do
      do_streaming_chat_completion(params, config, inspect_request?, inspect_response?)
    else
      do_chat_completion(params, config, inspect_request?, inspect_response?)
    end
  end

  defp do_streaming_chat_completion(params, config, inspect_request?, inspect_response?) do
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
                if inspect_response? do
                  IO.inspect(data, pretty: true, limit: :infinity, printable_limit: :infinity)
                end

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

          req = Req.new([url: url(config)] ++ options)

          if inspect_request? do
            IO.inspect(req, pretty: true, limit: :infinity, printable_limit: :infinity)
          end

          Req.post!(req)
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

  defp do_chat_completion(params, config, inspect_request?, inspect_response?) do
    options = Keyword.merge(http_options(config), json: params, auth: {:bearer, api_key(config)})
    req = Req.new([url: url(config)] ++ options)

    if inspect_request? do
      IO.inspect(req, pretty: true, limit: :infinity, printable_limit: :infinity)
    end

    response = Req.post!(req)

    if inspect_response? do
      IO.inspect(response, pretty: true, limit: :infinity, printable_limit: :infinity)
    end

    case response.status do
      200 -> {:ok, response.body}
      _ -> {:error, response.body}
    end
  end

  defp url(config), do: api_url(config) <> "/v1/chat/completions"
  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_key(config), do: Keyword.fetch!(config, :api_key)
  defp http_options(config), do: Keyword.fetch!(config, :http_options)

  defp config() do
    base_config = Application.get_env(:instructor, :openai, [])

    default_config = [
      api_url: "https://api.openai.com",
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
