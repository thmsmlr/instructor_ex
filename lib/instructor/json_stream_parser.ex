defmodule Instructor.JSONStreamParser do
  def parse(chunks) do
    chunks
    |> Jaxon.Stream.from_enumerable()
    |> Jaxon.Stream.values()
    |> Stream.transform(nil, fn
      {_loc, :end}, root ->
        {[], root}

      {loc, :start_object}, root ->
        root = json_insert_in(root, loc, %{})
        {[root], root}

      {loc, :start_array}, root ->
        root = json_insert_in(root, loc, [])
        {[root], root}

      {loc, val}, root ->
        root = json_insert_in(root, loc, val)
        {[root], root}
    end)
  end

  defp json_insert_in(_root, [], value) do
    value
  end

  defp json_insert_in(root, [index], value) when is_number(index) and is_list(root) do
    List.insert_at(root, index, value)
  end

  defp json_insert_in(root, [key], value) when is_binary(key) and is_map(root) do
    Map.put(root, key, value)
  end

  defp json_insert_in(root, [key | rest], value) when is_binary(key) and is_map(root) do
    Map.put(root, key, json_insert_in(root[key], rest, value))
  end

  defp json_insert_in(root, [index | rest], value) when is_number(index) and is_list(root) do
    List.update_at(root, index, fn subroot ->
      json_insert_in(subroot, rest, value)
    end)
  end
end
