defmodule Instructor.Adapters.OpenAI do
  @moduledoc """
  Documentation for `Instructor.Adapters.OpenAI`.
  """
  @behaviour Instructor.Adapter

  @impl true
  def chat_completion(params) do
    # Peel off instructor only parameters
    # TODO: Maybe refactor this? we'll see
    {_, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :max_retries)
    {_, params} = Keyword.pop(params, :mode)
    {config, params} = Keyword.pop(params, :config, %OpenAI.Config{})

    OpenAI.chat_completion(params, config)
  end
end
