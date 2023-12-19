defmodule Instructor.Adapters.Llamacpp do
  @moduledoc """
  Runs against the llama.cpp server. To be clear this calls the llamacpp specific
  endpoints, not the open-ai compliant ones.

  You can read more about it here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server
  """
  alias Instructor.JSONSchema
  alias Instructor.GBNF

  @behaviour Instructor.Adapter

  @doc """
  Run a completion against the llama.cpp server, not the open-ai compliant one.
  This gives you more specific control over the grammar, and the ability to
  provide other parameters to the specific LLM invocation.

  You can read more about the parameters here:
    https://github.com/ggerganov/llama.cpp/tree/master/examples/server

  ## Examples

    iex> Instructor.chat_completion(%{
    ...>   model: "mistral-7b-instruct",
    ...>   messages: [
    ...>     %{ role: "user", content: "Classify the following text: Hello I am a Nigerian prince and I would like to send you money!" },
    ...>   ],
    ...>   response_model: response_model,
    ...>   temperature: 0.5,
    ...> })
  """
  @impl true
  def chat_completion(params, _config \\ nil) do
    {response_model, params} = Keyword.pop!(params, :response_model)

    json_schema = JSONSchema.from_ecto_schema(response_model)
    grammar = GBNF.from_json_schema(json_schema)
    [%{role: "user", content: question} | _] = Keyword.get(params, :messages, [])

    prompt = """
    As a genius expert, your task is to understand the content and provide the parsed objects in json that match the following json_schema:\n

    #{grammar}

    [INST] #{question} [/INST]
    """

    response =
      Req.post!("http://localhost:8080/completion",
        json: %{grammar: grammar, prompt: prompt},
        receive_timeout: 60_000
      )

    case response do
      %{status: 200, body: %{"content" => params}} ->
        {:ok, params}
      _ ->
        nil
    end
  end
end
