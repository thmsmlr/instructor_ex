defmodule Instructor.Adapters.Groq do
  @moduledoc """
  Adapter for Groq Cloud API.  Using the OpenAI API compatible endpoint.

  ## Configuration

  ```elixir
  config :instructor, adapter: Instructor.Adapters.Groq, groq: [
    api_key: "your_api_key"
  ]
  ```

  or at runtime:

  ```elixir
  Instructor.chat_completion(..., [
    adapter: Instructor.Adapters.Groq,
    api_key: "your_api_key"
  ])
  ```

  For more configurations, see Instructor.Adapters.OpenAI for more details as this adapter inherits functionality from it.
  To get a Groq API key, see [Groq Cloud](https://groq.com/cloud).
  """

  @behaviour Instructor.Adapter
  alias Instructor.Adapters

  @supported_modes [:tools]

  @impl true
  def chat_completion(params, user_config \\ nil) do
    config = config(user_config)
    mode = params[:mode]

    if mode not in @supported_modes do
      raise "Unsupported mode #{mode} for Groq"
    end

    Adapters.OpenAI.chat_completion(params, config)
  end

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI

  defp config(nil), do: config(Application.get_env(:instructor, :groq, []))

  defp config(base_config) do
    default_config = [
      api_url: "https://api.groq.com/openai",
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
