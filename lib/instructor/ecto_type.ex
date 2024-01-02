defmodule Instructor.EctoType do
  @callback to_json_schema() :: map()

  def __using__(_) do
    quote do
      @behaviour Instructor.EctoType
    end
  end
end
