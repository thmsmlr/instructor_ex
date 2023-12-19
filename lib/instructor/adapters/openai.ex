defmodule Instructor.Adapters.OpenAI do
  @moduledoc """
  Documentation for `Instructor.Adapters.OpenAI`.
  """
  alias Instructor.JSONSchema

  @behaviour Instructor.Adapter

  @impl true
  def chat_completion(params, config \\ %OpenAI.Config{}) do
    {response_model, params} = Keyword.pop!(params, :response_model)

    json_schema = JSONSchema.from_ecto_schema(response_model)

    params =
      Keyword.update(params, :messages, [], fn messages ->
        sys_message = %{
          role: "system",
          content: """
          As a genius expert, your task is to understand the content and provide the parsed objects in json that match the following json_schema:\n

          #{json_schema}

          ```json
          """
        }

        [sys_message | messages]
      end)

    {:ok, %{choices: [%{"message" => %{"content" => response}}]}} =
      OpenAI.chat_completion(params, config)

    {:ok, response}
  end
end
