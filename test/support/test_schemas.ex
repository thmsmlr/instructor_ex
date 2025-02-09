defmodule InstructorTest.DemoWithDocumentation do
  @moduledoc """
  We have to do this because .exs files are not compiled and therefore you can't fetch
  the docs from the schema.

  Solution indirectly found here:
      https://stackoverflow.com/questions/73965602/why-cant-i-import-test-modules-directly-into-other-tests-in-elixir
  """
  use Ecto.Schema
  use Instructor

  @doc """
  Hello world
  """
  @primary_key false
  embedded_schema do
    field(:string, :string)
  end
end

defmodule InstructorTest.DemoRawEctoSchema do
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:string, :string)
  end
end

defmodule InstructorTest.DemoWithUseInstructorButOldDoc do
  use Instructor
  use Ecto.Schema

  @doc """
  Hello world
  """
  @primary_key false
  embedded_schema do
    field(:string, :string)
  end
end

defmodule InstructorTest.DemoWithUseInstructorAndNewDoc do
  use Ecto.Schema
  use Instructor

  @llm_doc "Hello world"
  @primary_key false
  embedded_schema do
    field(:string, :string)
  end
end
