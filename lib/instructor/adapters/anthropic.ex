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
    # stream = Keyword.get(params, :stream, false)
    params = Enum.into(params, %{})

    # if stream do
    #   do_streaming_chat_completion(params, config)
    # else
    do_chat_completion(params, config)
    # end
  end

  defp do_chat_completion(params, config) do
    options =
      Keyword.merge(http_options(config),
        json: params,
        headers: [{"x-api-key", api_key(config)}, {"anthropic-version", " 2023-06-01"}]
      )

    response = Req.post!(url(config), options)

    case response.status do
      200 -> {:ok, to_openai_response(response.body)}
      _ -> {:error, response.body}
    end
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
  defp to_openai_response(%{"content" => [%{"text" => content_text, "type" => "text"}]}=_params) do
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
