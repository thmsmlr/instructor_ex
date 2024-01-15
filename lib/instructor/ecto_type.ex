defmodule Instructor.EctoType do
  @moduledoc """
  Instructor.EctoType is a behaviour that lets your implement your own custom Ecto.Type
    that works natively with Instructor.

  ## Example
      
    ```elixir
    defmodule MyCustomType do
      use Ecto.Type
      use Instructor.EctoType

      # ... See `Ecto.Type` for implementation details

      def to_json_schema() do
        %{
          type: "string",
          format: "email"
        }
      end
    end
    ```
  """
  @callback to_json_schema() :: map()

  def __using__(_) do
    quote do
      @behaviour Instructor.EctoType
    end
  end
end
