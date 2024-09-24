defmodule Instructor.Adapters.Anthropic do
  @moduledoc """
  Anthropic adapter for Instructor.
  """
  @behaviour Instructor.Adapter

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

    {system_prompt, messages} = params.messages |> Enum.split_with(&(&1[:role] == "system"))
    system_prompt = system_prompt |> Enum.map(& &1[:content]) |> Enum.join("\n")

    [tool] = params.tools
    tool = tool.function

    tool =
      tool
      |> Map.put("input_schema", tool["parameters"])
      |> Map.delete("parameters")

    params =
      params
      |> Map.put(:messages, messages)
      |> Map.put(:tools, [tool])
      |> Map.put(:tool_choice, %{"type" => "tool", "name" => tool["name"]})
      |> Map.put(:system, system_prompt)

    if stream do
      do_streaming_chat_completion(mode, params, config)
    else
      do_chat_completion(mode, params, config)
    end
  end

  defp do_chat_completion(mode, params, config) do
    options = get_anthropic_http_opts(config) |> Keyword.merge(json: params)

    case Req.post(url(config), options) do
      {:ok, %Req.Response{status: 200, body: body} = response} ->
        {:ok, response, parse_response_for_mode(mode, body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Unexpected HTTP response code: #{status}\n#{inspect(body)}"}

      e ->
        e
    end
  end

  defp do_streaming_chat_completion(mode, params, config) do
    pid = self()
    options = get_anthropic_http_opts(config) |> Keyword.merge(json: params)

    Stream.resource(
      fn ->
        Task.async(fn ->
          options =
            Keyword.merge(options,
              into: fn {:data, data}, {req, resp} ->
                send(pid, data)
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
    |> SSEStreamParser.parse()
    |> Stream.map(fn chunk -> parse_stream_chunk_for_mode(mode, chunk) end)
  end

  defp get_anthropic_http_opts(config) do
    Keyword.merge(http_options(config),
      headers: [{"x-api-key", api_key(config)}, {"anthropic-version", " 2023-06-01"}]
    )
  end

  defp parse_stream_chunk_for_mode(:tools, %{"type" => event})
       when event in [
              "message_start",
              "ping",
              "content_block_start",
              "content_block_stop",
              "message_stop",
              "message_delta",
              "completion"
            ] do
    ""
  end

  defp parse_stream_chunk_for_mode(:tools, %{
         "type" => "content_block_delta",
         "delta" => %{"partial_json" => delta, "type" => "input_json_delta"}
       }) do
    delta
  end

  defp parse_response_for_mode(:tools, %{"content" => [%{"input" => args, "type" => "tool_use"}]}) do
    args
  end

  defp url(config), do: api_url(config) <> "/v1/messages"

  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_key(config), do: Keyword.fetch!(config, :api_key)
  defp http_options(config), do: Keyword.fetch!(config, :http_options)

  defp config(nil), do: config(Application.get_env(:instructor, :anthropic, []))

  defp config(base_config) do
    default_config = [
      api_url: "https://api.anthropic.com/",
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
