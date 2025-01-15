defmodule Instructor.Union do
  use Flint.Type, extends: Flint.Types.Union
  @behaviour Instructor.EctoType

  @impl true
  def to_json_schema(%{types: types}) when is_list(types) do
    # "oneOf" isn't in the allowes JSON schema subset for
    # structued outputs (OpenAI)
    %{
      "anyOf" => Enum.map(types, &Instructor.EctoType.for_type/1)
    }
  end
end
