defmodule Instructor.GBNF do
  @base_json_gbnf """
  value  ::= (object | array | string | number | boolean | null) ws

  object ::=
    "{" ws (
        string ":" ws value
        ("," ws string ":" ws value)*
    )? "}"

  array  ::=
    "[" ws01 (
                value
        ("," ws01 value)*
    )? "]"

  string ::=
    "\\"" (string-char)* "\\""

  string-char ::= [^"\\\\] | "\\\\" (["\\\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]) # escapes

  number ::= integer ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
  integer ::= "-"? ([0-9] | [1-9] [0-9]*)
  boolean ::= "true" | "false"
  null ::= "null"

  # Optional space: by convention, applied in this grammar after literal chars when allowed
  ws ::= ([ \\t\\n] ws)?
  ws01 ::= ([ \\t\\n])?
  """

  def from_json_schema(json_schema) when is_binary(json_schema),
    do: json_schema |> Jason.decode!() |> from_json_schema

  def from_json_schema(json_schema) do
    # defs are guaranteed to be objects.. I think..
    defs =
      json_schema["$defs"]
      |> Enum.map_join("\n\n", fn {schema, definition} ->
        property_gbnfs =
          definition["properties"]
          |> Enum.map_join("\n", fn {property, val} ->
            "#{schema}-#{sanitize(property)} ::= \"\\\"#{property}\\\"\" \"\:\" ws01 #{for_type(val)}"
          end)

        schema_gbnf =
          definition["properties"]
          |> Enum.map_join(" \",\" ", fn {property, _val} ->
            "ws01 #{schema}-#{sanitize(property)}"
          end)
          |> then(&" \"{\" #{&1} \"}\" ws01 ")

        """
        #{schema} ::= #{schema_gbnf}
        #{property_gbnfs}
        """
      end)

    root =
      json_schema["allOf"]
      |> Enum.map_join(" | ", fn %{"$ref" => ref} ->
        ref |> String.split("/") |> Enum.at(-1)
      end)
      |> then(&"root ::= (#{&1}) ws01")

    """
    #{root}
    #{defs}
    #{@base_json_gbnf}
    """
  end

  defp sanitize(x), do: x |> String.replace("_", "-")

  defp for_type(%{"type" => "integer"}), do: "integer"
  defp for_type(%{"format" => "float", "type" => "number"}), do: "number"
  defp for_type(%{"type" => "boolean"}), do: "boolean"
  defp for_type(%{"type" => "string"}), do: "string"

  defp for_type(%{"items" => %{"type" => type}, "title" => "array", "type" => "array"}) do
    subtype = for_type(%{"type" => type})

    """
    array  ::=
        "[" ws01 (
                #{subtype}
            ("," ws01 #{subtype})*
        )? "]"
    """
  end

  defp for_type(%{"type" => "object", "additionalProperties" => %{"type" => type}}) do
    subtype = for_type(%{"type" => type})

    """
    object ::=
        "{" ws (
            string ":" ws #{subtype}
            ("," ws string ":" ws #{subtype})*
        )? "}"
    """
  end

  defp for_type(%{"type" => "string", "enum" => enum}),
    do: "(" <> Enum.map_join(enum, " | ", &"\"\\\"#{&1}\\\"\"") <> ")"
end
