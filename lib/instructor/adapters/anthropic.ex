defmodule Instructor.Adapters.Anthropic do
  @moduledoc """
  Adapter for Anthropic API.
  """
  @behaviour Instructor.Adapter
  @supported_modes [:tools]

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
      raise "Unsupported mode: #{mode}"
    end

    params =
      case mode do
        :tools ->
          Map.update!(params, :tools, fn tools ->
            tools
            |> Enum.map(fn tool ->
              %{
                name: tool.function["name"],
                description: tool.function["description"],
                input_schema: tool.function["parameters"]
              }
            end)
          end)
      end

    if stream do
      do_streaming_chat_completion(mode, params, config)
    else
      do_chat_completion(mode, params, config)
    end
  end

  @impl true
  def reask_messages(_raw_response, params, _config) do
    params[:messages]
  end

  defp do_chat_completion(_mode, params, config) do
    options = http_options(config) |> Keyword.merge(json: params)

    case Req.post(url(config), options) do
      {:ok, %Req.Response{status: 200, body: body} = response} ->
        {:ok, response, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Unexpected HTTP response code: #{status}\n#{inspect(body)}"}

      e ->
        e
    end
  end

  defp do_streaming_chat_completion(mode, params, config) do
    # TODO: Implement
  end

  defp url(config), do: api_url(config) <> "/v1/messages"

  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp http_options(config), do: Keyword.fetch!(config, :http_options)
  defp config(nil), do: config(Application.get_env(:instructor, :anthropic, []))

  defp config(base_config) do
    default_config = [
      api_url: "https://api.anthropic.com",
      api_path: "/v1/messages",
      auth_mode: :bearer,
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
