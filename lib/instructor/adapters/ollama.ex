defmodule Instructor.Adapters.Ollama do
  @moduledoc """
  Ollama adapter for Instructor.
  """
  @behaviour Instructor.Adapter
  alias Instructor.Adapters

  @supported_modes [:json, :tools]

  @impl true
  def chat_completion(params, config \\ nil) do
    default_config = [api_url: "http://localhost:11434", api_key: "ollama"]
    config = Keyword.merge(default_config, config || [])
    mode = params[:mode]

    if mode not in @supported_modes do
      raise "Unsupported mode: #{mode}"
    end

    Adapters.OpenAI.chat_completion(params, config)
  end

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI
end
