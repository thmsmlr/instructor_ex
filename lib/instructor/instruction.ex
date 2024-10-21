if Code.ensure_loaded?(Flint.Schema) do
  defmodule Instructor.Instruction do
    use Flint.Extension

    option :doc, default: "", validator: &is_binary/1, required: false

    defmacro __using__(_opts) do
      quote do
        use Instructor.Validator

        @impl true
        def validate_changeset(changeset, context \\ %{}) do
          __MODULE__
          |> struct!()
          |> changeset(changeset, Enum.into(context, []))
        end

        defoverridable validate_changeset: 1, validate_changeset: 2
      end
    end
  end
end
