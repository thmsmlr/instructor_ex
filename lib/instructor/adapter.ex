defmodule Instructor.Adapter do
  @moduledoc """
  Behavior for `Instructor.Adapter`.
  """
  @callback chat_completion(map(), [Keyword.t()], any()) :: any()
  @callback prompt(Keyword.t()) :: map()
end
