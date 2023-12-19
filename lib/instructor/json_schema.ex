defmodule Instructor.JSONSchema do
  @doc """
    Generates a JSON Schema from an Ecto schema.

    Note: This will output a correct JSON Schema for the given Ecto schema, but
    it will not necessarily be optimal, nor support all Ecto types.
  """
  def from_ecto_schema(ecto_schema) do
    defs =
      for schema <- bfs_from_ecto_schema([ecto_schema], %MapSet{}), into: %{} do
        {schema.title, schema}
      end

    title = title_for(ecto_schema)

    %{
      "$defs": defs,
      allOf: [
        %{
          "$ref": "#/$defs/#{title}"
        }
      ]
    }
    |> Jason.encode!()
  end

  defp fetch_ecto_schema_doc(ecto_schema) do
    ecto_schema_struct_literal = "%#{title_for(ecto_schema)}{}"

    case Code.fetch_docs(ecto_schema) do
      {_, _, _, _, _, _, docs} ->
        docs
        |> Enum.find_value(fn
          {_, _, [^ecto_schema_struct_literal], %{"en" => doc}, %{}} ->
            doc

          _ ->
            false
        end)

      {:error, _} ->
        nil
    end
  end

  defp bfs_from_ecto_schema([], _seen_schemas), do: []

  defp bfs_from_ecto_schema([ecto_schema | rest], seen_schemas) do
    seen_schemas = MapSet.put(seen_schemas, ecto_schema)

    properties =
      ecto_schema.__schema__(:fields)
      |> Enum.map(fn field ->
        type = ecto_schema.__schema__(:type, field)
        value = for_type(type)
        value = Map.merge(%{title: Atom.to_string(field)}, value)

        {field, value}
      end)
      |> Enum.into(%{})

    associations =
      ecto_schema.__schema__(:associations)
      |> Enum.map(&ecto_schema.__schema__(:association, &1))
      |> Enum.filter(&(&1.relationship != :parent))
      |> Enum.map(fn association ->
        field = association.field
        title = title_for(association.related)

        value =
          if association.cardinality == :many do
            %{
              items: %{"$ref": "#/$defs/#{title}"},
              title: title,
              type: "array"
            }
          else
            %{"$ref": "#/$defs/#{title}"}
          end

        {field, value}
      end)
      |> Enum.into(%{})

    properties = Map.merge(properties, associations)
    required = Map.keys(properties)
    title = title_for(ecto_schema)

    associated_schemas =
      ecto_schema.__schema__(:associations)
      |> Enum.map(&ecto_schema.__schema__(:association, &1).related)
      |> Enum.filter(&(!MapSet.member?(seen_schemas, &1)))

    embedded_schemas =
      ecto_schema.__schema__(:embeds)
      |> Enum.map(&ecto_schema.__schema__(:embed, &1).related)
      |> Enum.filter(&(!MapSet.member?(seen_schemas, &1)))

    rest =
      rest
      |> Enum.concat(associated_schemas)
      |> Enum.concat(embedded_schemas)
      |> Enum.uniq()

    schema =
      %{
        title: title,
        type: "object",
        required: required,
        properties: properties,
        description: fetch_ecto_schema_doc(ecto_schema)
      }

    [schema | bfs_from_ecto_schema(rest, seen_schemas)]
  end

  defp title_for(ecto_schema) do
    to_string(ecto_schema) |> String.trim_leading("Elixir.")
  end

  defp for_type(:id), do: %{type: "integer"}
  # defp for_type(:binary_id), do: %{type: "unsupported"}
  defp for_type(:integer), do: %{type: "integer"}
  defp for_type(:float), do: %{type: "number", format: "float"}
  defp for_type(:boolean), do: %{type: "boolean"}
  defp for_type(:string), do: %{type: "string"}
  # defp for_type(:binary), do: %{type: "unsupported"}
  defp for_type({:array, type}), do: %{type: "array", items: for_type(type)}
  defp for_type(:map), do: %{type: "object", additionalProperties: %{type: "string"}}

  defp for_type({:map, type}),
    do: %{type: "object", additionalProperties: for_type(type)}

  defp for_type(:decimal), do: %{type: "number", format: "float"}
  defp for_type(:date), do: %{type: "string"}
  defp for_type(:time), do: %{type: "string"}
  defp for_type(:time_usec), do: %{type: "string"}
  defp for_type(:naive_datetime), do: %{type: "string"}
  defp for_type(:naive_datetime_usec), do: %{type: "string"}
  defp for_type(:utc_datetime), do: %{type: "string"}
  defp for_type(:utc_datetime_usec), do: %{type: "string"}

  defp for_type(
         {:parameterized, Ecto.Embedded, %Ecto.Embedded{cardinality: :one, related: related}}
       ) do
    title = title_for(related)

    %{
      items: %{"$ref": "#/$defs/#{title}"},
      title: title,
      type: "array"
    }
  end

  defp for_type(
         {:parameterized, Ecto.Embedded, %Ecto.Embedded{cardinality: :many, related: related}}
       ) do
    %{"$ref": "#/$defs/#{title_for(related)}"}
  end

  defp for_type({:parameterized, Ecto.Enum, %{mappings: mappings}}) do
    %{
      type: "string",
      enum: Keyword.keys(mappings)
    }
  end
end
