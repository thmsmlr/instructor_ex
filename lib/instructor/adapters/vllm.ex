defmodule Instructor.Adapters.VLLM do
  @moduledoc """
  VLLM adapter for Instructor.

  ## Configuration

  ```elixir
  config :instructor, adapter: Instructor.Adapters.VLLM, vllm: [
    api_url: "http://localhost:8000" # (Optional) defaults to localhost:8000
  ]
  ```

  or at runtime:

  ```elixir
  Instructor.chat_completion(..., [
    adapter: Instructor.Adapters.VLLM,
    api_url: "http://localhost:8000" # (Optional) defaults to localhost:8000
  ])
  ```

  To get a VLLM API key, see [VLLM](https://vllm.ai/).
  """
  @behaviour Instructor.Adapter
  alias Instructor.Adapters

  @supported_modes [:json_schema]

  @impl true
  def chat_completion(params, config \\ nil) do
    default_config = [api_url: "http://localhost:8000", api_key: "vllm"]
    config = Keyword.merge(default_config, config || [])
    mode = params[:mode]

    if mode not in @supported_modes do
      raise "Unsupported mode: #{mode}"
    end

    params =
      case Enum.into(params, %{}) do
        %{response_format: %{json_schema: %{schema: schema}}} ->
          Keyword.put(params, :guided_json, schema)

        _ ->
          params
      end

    Adapters.OpenAI.chat_completion(params, config)
  end

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI
end
