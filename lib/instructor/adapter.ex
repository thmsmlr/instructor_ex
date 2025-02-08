defmodule Instructor.Adapter do
  @moduledoc """
  Behavior for `Instructor.Adapter`.
  """

  @type params :: [Keyword.t()]
  @type config :: any()
  @type raw_response :: any()
  @type stream :: Enumerable.t()

  @callback chat_completion(params(), config()) ::
              stream() | {:ok, raw_response(), String.t()} | {:error, String.t()}

  @callback reask_messages(raw_response(), params(), config()) :: [map()]
end
