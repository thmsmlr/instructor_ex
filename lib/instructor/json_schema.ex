defmodule Instructor.JSONSchema do
  import Instructor.EctoType

  @doc """
    Generates a JSON Schema from an Ecto schema.

    Note: This will output a correct JSON Schema for the given Ecto schema, but
    it will not necessarily be optimal, nor support all Ecto types.
  """
  def from_ecto_schema(%Ecto.Changeset{data: %{__struct__: module}}), do: from_ecto_schema(module)

  def from_ecto_schema(ecto_schema) do
    defs =
      for schema <- bfs_from_ecto_schema([ecto_schema], %MapSet{}), into: %{} do
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

  defp fetch_ecto_schema_doc(ecto_schema) when is_ecto_schema(ecto_schema) do
    ecto_schema_struct_literal = "%#{title_for(ecto_schema)}{}"

    case Code.fetch_docs(ecto_schema) do
      {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, _} ->
        module_doc

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

  defp bfs_from_ecto_schema([ecto_schema | rest], seen_schemas)
       when is_ecto_schema(ecto_schema) do
    seen_schemas = MapSet.put(seen_schemas, ecto_schema)

    field_docs =
      try do
        ecto_schema.__schema__(:extra_options)
        |> Enum.map(fn {field, opts} ->
          {field, Keyword.get(opts, :doc, "")}
        end)
      rescue
        _ ->
          []
      end

    field_patterns =
      try do
        ecto_schema.__schema__(:extra_options)
        |> Enum.map(fn {field, opts} ->
          {field, Keyword.get(opts, :format)}
        end)
      rescue
        _ ->
          []
      end

    properties =
      ecto_schema.__schema__(:fields)
      |> Enum.map(fn field ->
        type = ecto_schema.__schema__(:type, field)
        field_doc = Keyword.get(field_docs, field, "") |> String.trim()
        field_pattern = Keyword.get(field_patterns, field)
        value = for_type(type)

        value =
          if field in ecto_schema.__schema__(:embeds) do
            value
          else
            Map.merge(%{title: Atom.to_string(field)}, value)
          end

        value =
          if field_doc != "" do
            Map.update(value, :description, field_doc, fn desc ->
              field_doc =
                cond do
                  field_doc == "" ->
                    ""

                  String.ends_with?(field_doc, ".") ->
                    field_doc <> " "

                  true ->
                    field_doc <> ". "
                end

              field_doc <> desc
            end)
          else
            value
          end

        value =
          if type == :string && match?(%Regex{}, field_pattern) do
            Map.put(value, :pattern, Regex.source(field_pattern))
          else
            value
          end

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
              # title: title,
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

    [schema | bfs_from_ecto_schema(rest, seen_schemas)]
  end

  defp bfs_from_ecto_schema([ecto_types | rest], seen_schemas)
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

    [schema | bfs_from_ecto_schema(rest, seen_schemas)]
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

  @doc """
  Traverses a tree structure of maps and lists, allowing the user to update or remove elements.

  ## Parameters
    - tree: The tree structure to traverse (can be a map, list, or any other type)
    - fun: A function that takes an element and returns either:
      - An updated element
      - nil to remove the element
      - The original element if no changes are needed

  ## Returns
    The updated tree structure
  """
  def traverse_and_update(tree, fun) when is_map(tree) do
    tree
    |> Enum.map(fn {k, v} -> {k, traverse_and_update(v, fun)} end)
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.into(%{})
    |> fun.()
  end

  def traverse_and_update(tree, fun) when is_list(tree) do
    tree
    |> Enum.map(fn elem -> traverse_and_update(elem, fun) end)
    |> Enum.filter(&(&1 != nil))
    |> fun.()
  end

  def traverse_and_update(tree, fun), do: fun.(tree)
end
