defmodule Instructor.Types.Enum do
  @moduledoc """
  A custom Ecto type for enumerated values with extended JSON Schema attributes.

  This type allows you to define string enums with static or dynamic values.

  ## Example with static values:
      schema "tasks" do
        field :status, Instructor.Types.Enum,
          values: ["pending", "active", "completed"],
          description: "Current status of the task"
      end

  ## Example with dynamic values:
      schema "projects" do
        field :user_id, Instructor.Types.Enum,
          values: fn -> MyApp.Users.list_user_ids() end,
          description: "ID of the user who owns this project"
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
  def cast(_value, _opts), do: :error

  # Load/dump with options
  def load(_opts, value), do: {:ok, value}
  def dump(_opts, value), do: {:ok, value}

  # These are required by Ecto.ParameterizedType
  def embed_as(_opts, _format), do: :self
  def equal?(opts, a, b), do: a == b

  # Dump with options and dumper function (3-arity version for ParameterizedType)
  def dump(value, _dumper, _opts), do: {:ok, value}

  # Load with options and loader function (3-arity version for ParameterizedType)
  def load(value, _loader, _opts), do: {:ok, value}

  # JSON Schema generation
  def to_json_schema(opts, context \\ %{}) do
    dbg(to_json_schema: {opts, context})
    values = get_values(opts[:values], context)

    %{
      "type" => "string",
      "enum" => values
    }
    |> maybe_add("description", opts[:description], context)
  end

  defp get_values(values, context) when is_function(values, 1), do: values.(context)
  defp get_values(values, _context) when is_list(values), do: values
  defp get_values(_, _context), do: []

  defp maybe_add(map, _key, nil, _context), do: map
  defp maybe_add(map, key, value, context) when is_function(value, 1), do: Map.put(map, key, value.(context))
  defp maybe_add(map, key, value, _context), do: Map.put(map, key, value)
end
