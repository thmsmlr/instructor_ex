Code.compiler_options(ignore_module_conflict: true, docs: true, debug_info: true)

defmodule GBNFTest do
  use ExUnit.Case, async: true

  alias Instructor.GBNF
  alias Instructor.JSONSchema

  test "basic types" do
    defmodule Demo do
      use Ecto.Schema

      # Be explicit about all fields in this test
      @primary_key false
      embedded_schema do
        # field(:binary_id, :binary_id)
        field(:integer, :integer)
        field(:float, :float)
        field(:boolean, :boolean)
        field(:string, :string)
        # field(:binary, :binary)
        field(:array, {:array, :string})
        field(:map, :map)
        field(:map_two, {:map, :string})
        field(:decimal, :decimal)
        field(:date, :date)
        field(:time, :time)
        field(:time_usec, :time_usec)
        field(:naive_datetime, :naive_datetime)
        field(:naive_datetime_usec, :naive_datetime_usec)
        field(:utc_datetime, :utc_datetime)
        field(:utc_datetime_usec, :utc_datetime_usec)
      end
    end

    gbnf =
      Demo
      |> JSONSchema.from_ecto_schema()
      |> GBNF.from_json_schema()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    expected_gbnf =
      """
      root ::=  "{" ws01 root-array "," ws01 root-boolean "," ws01 root-date "," ws01 root-decimal "," ws01 root-float "," ws01 root-integer "," ws01 root-map "," ws01 root-map-two "," ws01 root-naive-datetime "," ws01 root-naive-datetime-usec "," ws01 root-string "," ws01 root-time "," ws01 root-time-usec "," ws01 root-utc-datetime "," ws01 root-utc-datetime-usec "}" ws01
      root-array ::= "\\"array\\"" ":" ws01 array  ::=
      "[" ws01 (
              string
          ("," ws01 string)*
      )? "]"

      root-boolean ::= "\\"boolean\\"" ":" ws01 boolean
      root-date ::= "\\"date\\"" ":" ws01 date
      root-decimal ::= "\\"decimal\\"" ":" ws01 number
      root-float ::= "\\"float\\"" ":" ws01 number
      root-integer ::= "\\"integer\\"" ":" ws01 integer
      root-map ::= "\\"map\\"" ":" ws01 object ::=
      "{" ws (
          string ":" ws string
          ("," ws string ":" ws string)*
      )? "}"

      root-map-two ::= "\\"map_two\\"" ":" ws01 object ::=
      "{" ws (
          string ":" ws string
          ("," ws string ":" ws string)*
      )? "}"

      root-naive-datetime ::= "\\"naive_datetime\\"" ":" ws01 datetime
      root-naive-datetime-usec ::= "\\"naive_datetime_usec\\"" ":" ws01 datetime
      root-string ::= "\\"string\\"" ":" ws01 string
      root-time ::= "\\"time\\"" ":" ws01 string
      root-time-usec ::= "\\"time_usec\\"" ":" ws01 string
      root-utc-datetime ::= "\\"utc_datetime\\"" ":" ws01 datetime
      root-utc-datetime-usec ::= "\\"utc_datetime_usec\\"" ":" ws01 datetime

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

      # ISO8601 date format
      date ::= [0-9]{4} "-" [0-9]{2} "-" [0-9]{2}
      datetime ::= date "T" [0-9]{2} ":" [0-9]{2} ":" [0-9]{2} ("." [0-9]+)? ("Z" | ("+" | "-") [0-9]{2} ":" [0-9]{2})

      number ::= integer ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
      integer ::= "-"? ([0-9] | [1-9] [0-9]*)
      boolean ::= "true" | "false"
      null ::= "null"

      # Optional space: by convention, applied in this grammar after literal chars when allowed
      ws ::= ([ \\t\\n] ws)?
      ws01 ::= ([ \\t\\n])?
      """
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    assert gbnf == expected_gbnf
  end
end
