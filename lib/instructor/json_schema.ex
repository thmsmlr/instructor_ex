defmodule Instructor.JSONSchema do
  require Logger
  defguardp is_ecto_schema(mod) when is_atom(mod)
  defguardp is_ecto_types(types) when is_map(types)

  @doc """
    Generates a JSON Schema from an Ecto schema.

    Note: This will output a correct JSON Schema for the given Ecto schema, but
    it will not necessarily be optimal, nor support all Ecto types.
  """
  def from_ecto_schema(ecto_schema, schema_context \\ %{}) do
    do_deprecation_warning(ecto_schema)

    defs =
      for schema <- bfs_from_ecto_schema([ecto_schema], %MapSet{}, schema_context), into: %{} do
        {schema.title, schema}
      end

    title =
      if is_ecto_schema(ecto_schema) do
        title_for(ecto_schema)
      else
        "root"
      end

    title_ref = "#/$defs/#{title}"

    refs =
      find_all_values(defs, fn
        {_, ^title_ref} -> true
        _ -> false
      end)

    # Remove root from defs to save tokens if it's not referenced recursively
    {root, defs} =
      case refs do
        [^title_ref] -> {defs[title], defs}
        _ -> Map.pop(defs, title)
      end

    root
    |> then(
      &if map_size(defs) > 0 do
        Map.put(&1, :"$defs", defs)
      else
        &1
      end
    )
    |> Jason.encode!()
  end

  defp do_deprecation_warning(response_model) do
    is_ecto = is_ecto_schema(response_model)
    has_old_doc = fetch_old_ecto_schema_doc(response_model) != nil
    has_new_doc = fetch_new_ecto_schema_doc(response_model) != nil
    has_use_instructor = uses_use_instructor(response_model)

    cond do
      is_ecto and not has_use_instructor ->
        Logger.warning("""
          Using Ecto Schemas without `use Instructor` is deprecated.

          Please change your schema to include `use Instructor` and use the `@llm_doc` attribute to
          define your schema documentation you'd like to send to the LLM.
        """)

        true

      is_ecto and has_old_doc and not has_new_doc ->
        Logger.warning("""
          Using Ecto Schemas with the `@doc` attribute is deprecated.

          Please change your schema to include `use Instructor` and use the `@llm_doc` attribute to
          define your schema documentation you'd like to send to the LLM.
        """)

        true

      true ->
        false
    end
  end

  defp uses_use_instructor(ecto_schema) when is_ecto_schema(ecto_schema) do
    {:__llm_doc__, 0} in ecto_schema.__info__(:functions)
  end

  defp uses_use_instructor(_), do: false

  defp fetch_ecto_schema_doc(ecto_schema) when is_ecto_schema(ecto_schema) do
    fetch_new_ecto_schema_doc(ecto_schema) || fetch_old_ecto_schema_doc(ecto_schema)
  end

  defp fetch_ecto_schema_doc(_), do: nil

  defp fetch_new_ecto_schema_doc(ecto_schema) when is_ecto_schema(ecto_schema) do
    if function_exported?(ecto_schema, :__llm_doc__, 0) do
      ecto_schema.__llm_doc__()
    else
      nil
    end
  end

  defp fetch_new_ecto_schema_doc(_), do: nil

  defp fetch_old_ecto_schema_doc(ecto_schema) when is_ecto_schema(ecto_schema) do
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

  defp fetch_old_ecto_schema_doc(_), do: nil

  defp bfs_from_ecto_schema([], _seen_schemas, _schema_context), do: []

  defp bfs_from_ecto_schema([ecto_schema | rest], seen_schemas, schema_context)
       when is_ecto_schema(ecto_schema) do
    seen_schemas = MapSet.put(seen_schemas, ecto_schema)

    properties =
      ecto_schema.__schema__(:fields)
      |> Enum.map(fn field ->
        type = ecto_schema.__schema__(:type, field)
        value = for_type(type, schema_context)
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
    required = Map.keys(properties) |> Enum.sort()
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
        additionalProperties: false,
        required: required,
        properties: properties,
        description: fetch_ecto_schema_doc(ecto_schema) || ""
      }

    [schema | bfs_from_ecto_schema(rest, seen_schemas, schema_context)]
  end

  defp bfs_from_ecto_schema([ecto_types | rest], seen_schemas, schema_context)
       when is_ecto_types(ecto_types) do
    properties =
      for {field, type} <- ecto_types, into: %{} do
        {field, for_type(type)}
      end

    required = Map.keys(properties) |> Enum.sort()

    embedded_schemas =
      for {_field, {:parameterized, {Ecto.Embedded, %Ecto.Embedded{related: related}}}} <-
            ecto_types,
          is_ecto_schema(related) do
        related
      end

    rest =
      rest
      |> Enum.concat(embedded_schemas)
      |> Enum.uniq()
      |> Enum.filter(&(!MapSet.member?(seen_schemas, &1)))

    schema =
      %{
        title: "root",
        type: "object",
        additionalProperties: false,
        required: required,
        properties: properties
      }

    [schema | bfs_from_ecto_schema(rest, seen_schemas, schema_context)]
  end

  defp title_for(ecto_schema) when is_ecto_schema(ecto_schema) do
    to_string(ecto_schema) |> String.trim_leading("Elixir.")
  end

  # Find all values in a map or list that match a predicate
  defp find_all_values(map, pred) when is_map(map) do
    map
    |> Enum.flat_map(fn
      {key, val} ->
        cond do
          pred.({key, val}) ->
            [val]

          true ->
            find_all_values(val, pred)
        end
    end)
  end

  defp find_all_values(list, pred) when is_list(list) do
    list
    |> Enum.flat_map(fn
      val ->
        find_all_values(val, pred)
    end)
  end

  defp find_all_values(_, _pred), do: []

  defp for_type(:any, _), do: %{}
  defp for_type(:id, _), do: %{type: "integer", description: "Integer, e.g. 1"}
  defp for_type(:binary_id, _), do: %{type: "string"}
  defp for_type(:integer, _), do: %{type: "integer", description: "Integer, e.g. 1"}
  defp for_type(:float, _), do: %{type: "number", description: "Float, e.g. 1.27", format: "float"}
  defp for_type(:boolean, _), do: %{type: "boolean", description: "Boolean, e.g. true"}
  defp for_type(:string, _), do: %{type: "string", description: "String, e.g. 'hello'"}
  # defp for_type(:binary), do: %{type: "unsupported"}
  defp for_type({:array, type}, _), do: %{type: "array", items: for_type(type)}

  defp for_type(:map, _),
    do: %{
      type: "object",
      properties: %{},
      additionalProperties: false,
      description: "An object with arbitrary keys and values, e.g. { key: value }"
    }

  defp for_type({:map, type}, _),
    do: %{
      type: "object",
      properties: %{},
      additionalProperties: for_type(type),
      description: "An object with values of a type #{inspect(type)}, e.g. { key: value }"
    }

  defp for_type(:decimal, _), do: %{type: "number", format: "float"}

  defp for_type(:date, _),
    do: %{type: "string", description: "ISO8601 Date, e.g. \"2024-07-20\"", format: "date"}

  defp for_type(:time, _),
    do: %{
      type: "string",
      description: "ISO8601 Time, e.g. \"12:00:00\"",
      pattern: "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}$"
    }

  defp for_type(:time_usec, _),
    do: %{
      type: "string",
      description: "ISO8601 Time with microseconds, e.g. \"12:00:00.000000\"",
      pattern: "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}.[0-9]{6}$"
    }

  defp for_type(:naive_datetime, _),
    do: %{
      type: "string",
      description: "ISO8601 DateTime, e.g. \"2024-07-20T12:00:00\"",
      format: "date-time"
    }

  defp for_type(:naive_datetime_usec, _),
    do: %{
      type: "string",
      description: "ISO8601 DateTime with microseconds, e.g. \"2024-07-20T12:00:00.000000\"",
      format: "date-time"
    }

  defp for_type(:utc_datetime, _),
    do: %{
      type: "string",
      description: "ISO8601 DateTime, e.g. \"2024-07-20T12:00:00Z\"",
      format: "date-time"
    }

  defp for_type(:utc_datetime_usec, _),
    do: %{
      type: "string",
      description: "ISO8601 DateTime with microseconds, e.g. \"2024-07-20T12:00:00.000000Z\"",
      format: "date-time"
    }

  defp for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :many, related: related}}}, _
       )
       when is_ecto_schema(related) do
    title = title_for(related)

    %{
      items: %{"$ref": "#/$defs/#{title}"},
      title: title,
      type: "array"
    }
  end

  defp for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :many, related: related}}}, _
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

  defp for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :one, related: related}}}, _
       )
       when is_ecto_schema(related) do
    %{"$ref": "#/$defs/#{title_for(related)}"}
  end

  defp for_type(
         {:parameterized, {Ecto.Embedded, %Ecto.Embedded{cardinality: :one, related: related}}}, _
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

  defp for_type({:parameterized, {Ecto.Enum, %{mappings: mappings}}}, _) do
    %{
      type: "string",
      enum: Keyword.keys(mappings)
    }
  end

  defp for_type({:parameterized, {mod, opts}}, schema_context) when is_atom(mod) do
    if function_exported?(mod, :to_json_schema, 2) do
      mod.to_json_schema(opts, schema_context)
    else
      raise "Unsupported type: #{inspect(mod)}, please implement `to_json_schema/1` via `use Instructor.EctoType`"
    end
  end

  defp for_type(mod) do
    if function_exported?(mod, :to_json_schema, 0) do
      mod.to_json_schema()
    else
      raise "Unsupported type: #{inspect(mod)}, please implement `to_json_schema/0` via `use Instructor.EctoType`"
    end
  end

  @doc """
  Traverses a tree structure of maps and lists, allowing the user to update or remove elements.

  ## Parameters
    - tree: The tree structure to traverse (can be a map, list, or any other type)
    - fun: A function that takes either:
      - Just the element if include_path: false (default)
      - A tuple of {element, path} if include_path: true, where path is a list of keys to reach this element
    The function should return either:
      - An updated element
      - nil to remove the element
      - The original element if no changes are needed
    - opts: Optional keyword list of options
      - include_path: boolean, when true includes the path to each element in the callback (default: false)

  ## Returns
    The updated tree structure
  """
  def traverse_and_update(tree, fun, opts \\ []) do
    do_traverse_and_update(tree, fun, [], opts)
  end

  defp do_traverse_and_update(tree, fun, path, opts) when is_map(tree) do
    tree
    |> Enum.map(fn {k, v} -> {k, do_traverse_and_update(v, fun, path ++ [k], opts)} end)
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.into(%{})
    |> maybe_call_with_path(fun, path, opts)
  end

  defp do_traverse_and_update(tree, fun, path, opts) when is_list(tree) do
    tree
    |> Enum.with_index()
    |> Enum.map(fn {elem, idx} -> do_traverse_and_update(elem, fun, path ++ [idx], opts) end)
    |> Enum.filter(&(&1 != nil))
    |> maybe_call_with_path(fun, path, opts)
  end

  defp do_traverse_and_update(tree, fun, path, opts), do: maybe_call_with_path(tree, fun, path, opts)

  defp maybe_call_with_path(value, fun, path, opts) do
    if Keyword.get(opts, :include_path, false) do
      fun.({value, path})
    else
      fun.(value)
    end
  end
end
