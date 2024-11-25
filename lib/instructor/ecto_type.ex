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
  @callback to_json_schema(tuple()) :: map()

  @optional_callbacks to_json_schema: 0, to_json_schema: 1

  defguard is_ecto_schema(mod) when is_atom(mod)
  defguard is_ecto_types(types) when is_map(types)

  def title_for(ecto_schema) when is_ecto_schema(ecto_schema) do
    to_string(ecto_schema) |> String.trim_leading("Elixir.")
  end

  def for_type(:any), do: %{}
  def for_type(:id), do: %{type: "integer", description: "Integer, e.g. 1"}
  def for_type(:binary_id), do: %{type: "string"}
  def for_type(:integer), do: %{type: "integer", description: "Integer, e.g. 1"}
  def for_type(:float), do: %{type: "number", description: "Float, e.g. 1.27", format: "float"}
  def for_type(:boolean), do: %{type: "boolean", description: "Boolean, e.g. true"}
  def for_type(:string), do: %{type: "string", description: "String, e.g. 'hello'"}
  # def for_type(:binary), do: %{type: "unsupported"}
  def for_type({:array, type}), do: %{type: "array", items: for_type(type)}

  def for_type(:map),
    do: %{
      type: "object",
      properties: %{},
      additionalProperties: false,
      description: "An object with arbitrary keys and values, e.g. { key: value }"
    }

  def for_type({:map, type}),
    do: %{
      type: "object",
      properties: %{},
      additionalProperties: for_type(type),
      description: "An object with values of a type #{inspect(type)}, e.g. { key: value }"
    }

  def for_type(:decimal), do: %{type: "number", format: "float"}

  def for_type(:date),
    do: %{type: "string", description: "ISO8601 Date, e.g. \"2024-07-20\"", format: "date"}

  def for_type(:time),
    do: %{
      type: "string",
      description: "ISO8601 Time, e.g. \"12:00:00\"",
      pattern: "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}$"
    }

  def for_type(:time_usec),
    do: %{
      type: "string",
      description: "ISO8601 Time with microseconds, e.g. \"12:00:00.000000\"",
      pattern: "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}.[0-9]{6}$"
    }

  def for_type(:naive_datetime),
    do: %{
      type: "string",
      description: "ISO8601 DateTime, e.g. \"2024-07-20T12:00:00\"",
      format: "date-time"
    }

  def for_type(:naive_datetime_usec),
    do: %{
      type: "string",
      description: "ISO8601 DateTime with microseconds, e.g. \"2024-07-20T12:00:00.000000\"",
      format: "date-time"
    }

  def for_type(:utc_datetime),
    do: %{
      type: "string",
      description: "ISO8601 DateTime, e.g. \"2024-07-20T12:00:00Z\"",
      format: "date-time"
    }

  def for_type(:utc_datetime_usec),
    do: %{
      type: "string",
      description: "ISO8601 DateTime with microseconds, e.g. \"2024-07-20T12:00:00.000000Z\"",
      format: "date-time"
    }

  def for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :many, related: related}}}
       )
       when is_ecto_schema(related) do
    title = title_for(related)

    %{
      items: %{"$ref": "#/$defs/#{title}"},
      title: title,
      type: "array"
    }
  end

  def for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :many, related: related}}}
       )
       when is_ecto_types(related) do
    properties =
      for {field, type} <- related, into: %{} do
        {field, for_type(type)}
      end

    required = Map.keys(properties) |> Enum.sort()

    %{
      items: %{
        type: "object",
        required: required,
        properties: properties
      },
      type: "array"
    }
  end

  def for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :one, related: related}}}
       )
       when is_ecto_schema(related) do
    %{"$ref": "#/$defs/#{title_for(related)}"}
  end

  def for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :one, related: related}}}
       )
       when is_ecto_types(related) do
    properties =
      for {field, type} <- related, into: %{} do
        {field, for_type(type)}
      end

    required = Map.keys(properties) |> Enum.sort()

    %{
      type: "object",
      required: required,
      properties: properties,
      additionalProperties: false
    }
  end

  def for_type({:parameterized, {Ecto.Enum, %{mappings: mappings}}}) do
    %{
      type: "string",
      enum: Keyword.keys(mappings)
    }
  end

  def for_type({:parameterized, {mod, params}}) do
    if function_exported?(mod, :to_json_schema, 1) do
      mod.to_json_schema(params)
    else
      raise "Unsupported type: #{inspect(mod)}, please implement `to_json_schema/1` via `use Instructor.EctoType`"
    end
  end

  def for_type(mod) do
    if function_exported?(mod, :to_json_schema, 0) do
      mod.to_json_schema()
    else
      raise "Unsupported type: #{inspect(mod)}, please implement `to_json_schema/0` via `use Instructor.EctoType`"
    end
  end

  def __using__(_) do
    quote do
      @behaviour Instructor.EctoType
      import Instructor.EctoType
    end
  end
end
