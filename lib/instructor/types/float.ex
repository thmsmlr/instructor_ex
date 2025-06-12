defmodule Instructor.Types.Float do
  @moduledoc """
  A custom Ecto type for float with extended JSON Schema attributes.

  This type extends the basic Ecto float type with additional JSON Schema properties
  like description, minimum, maximum, multipleOf, etc.

  ## Example
      schema "products" do
        field :quantity, Instructor.Types.Float,
          description: "Available quantity",
          minimum: 0,
          maximum: 1000

        field :price_cents, Instructor.Types.Float,
          description: "Price in cents",
          minimum: 0,
          multipleOf: 1
      end
  """
  use Ecto.ParameterizedType
  use Instructor.EctoType

  # Initialize the type with the given parameters
  def init(opts), do: Enum.into(opts, %{})

  # The underlying Ecto type
  def type(_opts), do: :float

  # Cast with options
  def cast(value, opts) when is_float(value), do: {:ok, value}

  def cast(value, opts) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  def cast(_opts, _), do: :error

  # Load/dump with options
  def load(_opts, value), do: {:ok, value}
  def dump(_opts, value), do: {:ok, value}

  # These are required by Ecto.ParameterizedType
  def embed_as(_opts, _format), do: :self
  def equal?(opts, a, b), do: a == b

  # Dump with options and dumper function (3-arity version for ParameterizedType)
  def dump(value, _dumper, _opts), do: {:ok, value}

  # JSON Schema generation
  def to_json_schema(opts, context \\ %{}) do
    base = %{"type" => "float"}

    base
    |> maybe_add("description", opts[:description], context)
    |> maybe_add("minimum", opts[:minimum], context)
    |> maybe_add("maximum", opts[:maximum], context)
    |> maybe_add("exclusiveMinimum", opts[:exclusiveMinimum], context)
    |> maybe_add("exclusiveMaximum", opts[:exclusiveMaximum], context)
    |> maybe_add("multipleOf", opts[:multipleOf], context)
  end

  defp maybe_add(map, _key, nil, _context), do: map

  defp maybe_add(map, key, value, context) when is_function(value, 1),
    do: Map.put(map, key, value.(context))

  defp maybe_add(map, key, value, _context), do: Map.put(map, key, value)
end
