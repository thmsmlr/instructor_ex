defmodule Instructor.Validator do
  @callback validate_changeset(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  @optional_callbacks [
    validate_changeset: 1
  ]

  defmacro __using__(_) do
    quote do
      @behaviour Instructor.Validator
    end
  end
end
