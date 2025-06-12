defmodule Instructor.Types.String do
  @moduledoc """
  A custom Ecto type for strings with extended JSON Schema attributes.

  This type extends the basic Ecto string type with additional JSON Schema properties
  like description, format, min/max length, pattern, etc.

  ## Example
      schema "users" do
        field :name, Instructor.Types.String,
          description: "User's full name",
          minLength: 2,
          maxLength: 50

        field :email, Instructor.Types.String,
          description: "User's email address",
          format: "email"
      end
  """
  use Ecto.ParameterizedType
  use Instructor.EctoType

  # Initialize the type with the given parameters
  def init(opts), do: Enum.into(opts, %{})

  # The underlying Ecto type
  def type(_opts), do: :string

  # Cast with options
  def cast(value, opts) when is_binary(value), do: {:ok, value}
  def cast(value, opts) do
    :error
  end

  # Load with options
  def load(_opts, value), do: {:ok, value}

  # Dump with options (2-arity version for compatibility)
  def dump(_opts, value), do: {:ok, value}

  # Dump with options and dumper function (3-arity version for ParameterizedType)
  def dump(value, _dumper, _opts), do: {:ok, value}

  # Load with options and loader function (3-arity version for ParameterizedType)
   def load(value, _loader, _opts), do: {:ok, value}

  # These are required by Ecto.ParameterizedType
  def embed_as(_opts, _format), do: :self
  def equal?(opts, a, b), do: a == b

  # JSON Schema generation
  def to_json_schema(opts, context \\ %{}) do
    base = %{"type" => "string"}

    base
    |> maybe_add("description", opts[:description], context)
    |> maybe_add("minLength", opts[:minLength], context)
    |> maybe_add("maxLength", opts[:maxLength], context)
    |> maybe_add("pattern", opts[:pattern], context)
    |> maybe_add("format", opts[:format], context)
  end

  defp maybe_add(map, _key, nil, _context), do: map
  defp maybe_add(map, key, value, context) when is_function(value, 1), do: Map.put(map, key, value.(context))
  defp maybe_add(map, key, value, _context), do: Map.put(map, key, value)
end
