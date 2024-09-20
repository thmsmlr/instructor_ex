defmodule Instructor.Adapters.Llamacpp do
  @moduledoc """
  Runs against the llama.cpp server. To be clear this calls the llamacpp specific
  endpoints, not the open-ai compliant ones.

  You can read more about it here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server
  """
  alias Instructor.Adapters

  @behaviour Instructor.Adapter

  @doc """
  Run a completion against the llama.cpp server, not the open-ai compliant one.
  This gives you more specific control over the grammar, and the ability to
  provide other parameters to the specific LLM invocation.

  You can read more about the parameters here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server

  ## Examples

    iex> Instructor.chat_completion(
    ...>   model: "llama3.1-8b-instruct",
    ...>   messages: [
    ...>     %{ role: "user", content: "Classify the following text: Hello I am a Nigerian prince and I would like to send you money!" },
    ...>   ],
    ...>   response_model: response_model,
    ...>   temperature: 0.5,
    ...> )
  """
  @impl true
  def chat_completion(params, config \\ nil) do
    mode = params[:mode]

    params =
      case mode do
        :json_schema ->
          update_in(params, [:response_format], fn response_format ->
            %{
              type: "json_object",
              schema: response_format.json_schema.schema
            }
          end)

        _ ->
          raise "Unsupported mode: #{mode}"
      end

    default_config = [api_url: "http://localhost:8080", api_key: "llamacpp"]
    config = Keyword.merge(default_config, config || [])
    Adapters.OpenAI.chat_completion(params, config)
  end

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI
end
