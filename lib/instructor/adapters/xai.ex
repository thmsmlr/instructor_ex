defmodule Instructor.Adapters.XAI do
  @moduledoc """
  Adapter for XAI API to access the Grok models.

  ## Configuration

  ```elixir
  config :instructor, adapter: Instructor.Adapters.XAI, xai: [
    api_key: "your_api_key" # Will use XAI_API_KEY environment variable if not provided
  ]
  ```

  or at runtime:

  ```elixir
  Instructor.chat_completion(..., [
    adapter: Instructor.Adapters.XAI,
    api_key: "your_api_key" # Will use XAI_API_KEY environment variable if not provided
  ])
  ```
  """

  @behaviour Instructor.Adapter
  alias Instructor.Adapters

  @supported_modes [:tools, :json_schema]

  @impl true
  def chat_completion(params, user_config \\ nil) do
    config = config(user_config)
    mode = params[:mode]

    if mode not in @supported_modes do
      raise "Unsupported mode #{mode} for XAI"
    end

    Adapters.OpenAI.chat_completion(params, config)
  end

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI

  defp config(nil), do: config(Application.get_env(:instructor, :xai, []))

  defp config(base_config) do
    default_config = [
      api_url: "https://api.x.ai",
      api_key: System.get_env("XAI_API_KEY"),
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
