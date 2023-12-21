defmodule InstructorTest.DemoWithDocumentation do
  @moduledoc """
  We have to do this because .exs files are not compiled and therefore you can't fetch
  the docs from the schema.

  Solution indirectly found here:
      https://stackoverflow.com/questions/73965602/why-cant-i-import-test-modules-directly-into-other-tests-in-elixir
  """
  use Ecto.Schema

  @doc """
  Hello world
  """
  @primary_key false
  embedded_schema do
    field(:string, :string)
  end
end
