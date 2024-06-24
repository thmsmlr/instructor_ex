defmodule Instructor.Adapters.Anthropic do
  @moduledoc """
  Documentation for #{__MODULE__}.
  """
  @behaviour Instructor.Adapter

  @impl true
  def chat_completion(params, config \\ nil) do
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

  defp do_chat_completion(params, config) do
    # options =
    #   Keyword.merge(http_options(config),
    #     json: params,
    #     headers: [{"x-api-key", api_key(config)}, {"anthropic-version", " 2023-06-01"}]
    #   )
    options = get_anthropic_http_opts(config) |> Keyword.merge(json: params)

    response = Req.post!(url(config), options)

    case response.status do
      200 -> {:ok, to_openai_response(response.body)}
      _ -> {:error, response.body}
    end
  end

  defp do_streaming_chat_completion(params, config) do
    pid = self()
    options = get_anthropic_http_opts(config) |> Keyword.merge(json: params)

    Stream.resource(
      fn ->
        Task.async(fn ->
          options =
            Keyword.merge(options,
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
                  chunk = to_openai_streaming_response(chunk)
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

  defp get_anthropic_http_opts(config) do
    Keyword.merge(http_options(config),
      headers: [{"x-api-key", api_key(config)}, {"anthropic-version", " 2023-06-01"}]
    )
  end

  @doc """
  Anthropic has event types and data associated with each.

  Event Types:
    "message_start"
    "message_delta"
    "message_stop"
    "content_block_start"
    "content_block_delta"
    "content_block_stop"
    "completion"
    "ping"
    "error"

  Expected output:
    %{"choices" => [%{"delta" => %{"content" => chunk}}]}
  """
  def to_openai_streaming_response(%{"type" => event})
      when event in [
             "message_start",
             "content_block_stop",
             "ping",
             "message_stop",
             "message_delta",
             "completion"
           ] do
    final_massage_into_openai_response("")
  end

  def to_openai_streaming_response(
        %{
          "type" => "content_block_start",
          "content_block" => %{"type" => "text", "text" => returned_text}
        }
      ) do
    final_massage_into_openai_response(returned_text)
  end

  def to_openai_streaming_response(
        %{
          "type" => "content_block_delta",
          "delta" => %{"type" => "text_delta", "text" => returned_text}
        }
      ) do
    final_massage_into_openai_response(returned_text)
  end

  defp final_massage_into_openai_response("```") do
    %{"choices" => [%{"delta" => %{"content" => ""}}]}
  end

  defp final_massage_into_openai_response(chunk) do
    chunk = chunk |> String.trim_trailing("```")
    %{"choices" => [%{"delta" => %{"content" => chunk}}]}
  end

  # %{
  #   "content" => [
  #     %{
  #       "text" => "ACTUAL RESPONSE ",
  #       "type" => "text"
  #     }
  #   ],
  #   "id" => "msg_01W35ZRGGrPaL4fXqgB5fHDs",
  #   "model" => "claude-3-haiku-20240307",
  #   "role" => "assistant",
  #   "stop_reason" => "end_turn",
  #   "stop_sequence" => nil,
  #   "type" => "message",
  #   "usage" => %{"input_tokens" => 243, "output_tokens" => 132}
  # }
  defp to_openai_response(%{"content" => [%{"text" => content_text, "type" => "text"}]} = _params) do
    # optionally, remove ```
    content_text = content_text |> String.trim_trailing("\n```")

    %{
      "choices" => [
        %{
          "message" => %{"content" => content_text}
        }
      ]
    }
  end

  defp url(config), do: api_url(config) <> "/v1/messages"

  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_key(config), do: Keyword.fetch!(config, :api_key)
  defp http_options(config), do: Keyword.fetch!(config, :http_options)

  defp config() do
    base_config = Application.get_env(:instructor, :anthropic, [])

    default_config = [
      api_url: "https://api.anthropic.com/",
      # https://github.com/wojtekmach/req/issues/309
      http_options: [receive_timeout: 60_000, connect_options: [protocols: [:http2]]]
    ]

    Keyword.merge(default_config, base_config)
  end
end
