defmodule Instructor.ErrorFormatter do
  @moduledoc false

  alias Ecto.Changeset

  def format_errors(%Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn _changeset, _field, {msg, opts} ->
        msg =
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)

        "#{msg}"
      end)

    format_errors(errors)
  end

  def format_errors(errors) do
    format_errors(errors, [])
  end

  defp format_errors(%{} = errors, path) do
    errors
    |> Enum.map(fn {key, value} -> format_errors(value, path ++ [key]) end)
    |> Enum.join("\n")
  end

  defp format_errors([%{} = map | tail], path) do
    Enum.with_index([map | tail])
    |> Enum.map(fn {element, index} -> format_errors(element, path ++ [index]) end)
    |> Enum.join("\n")
  end

  defp format_errors([head | tail], path) do
    formatted_head = format_error(head, path)
    formatted_tail = format_errors(tail, path)

    [formatted_head, formatted_tail]
    |> Enum.filter(&(&1 != ""))
    |> Enum.join("\n")
  end

  defp format_errors([], _path), do: ""

  defp format_errors(value, path) when is_binary(value) do
    format_error(value, path)
  end

  defp format_error(error, path) do
    formatted_path =
      Enum.map_join(path, ".", fn
        element when is_integer(element) -> "[#{element}]"
        element -> to_string(element)
      end)

    "#{formatted_path} - #{error}"
  end
end
