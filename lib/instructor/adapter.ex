defmodule Instructor.Adapter do
  @moduledoc """
  Behavior for `Instructor.Adapter`.
  """
  @callback chat_completion([Keyword.t()], any()) :: any()
end
