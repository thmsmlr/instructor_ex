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
      root ::= (GBNFTest.Demo) ws01
      GBNFTest.Demo ::=  "{" ws01 GBNFTest.Demo-array "," ws01 GBNFTest.Demo-boolean "," ws01 GBNFTest.Demo-date "," ws01 GBNFTest.Demo-decimal "," ws01 GBNFTest.Demo-float "," ws01 GBNFTest.Demo-integer "," ws01 GBNFTest.Demo-map "," ws01 GBNFTest.Demo-map-two "," ws01 GBNFTest.Demo-naive-datetime "," ws01 GBNFTest.Demo-naive-datetime-usec "," ws01 GBNFTest.Demo-string "," ws01 GBNFTest.Demo-time "," ws01 GBNFTest.Demo-time-usec "," ws01 GBNFTest.Demo-utc-datetime "," ws01 GBNFTest.Demo-utc-datetime-usec "}" ws01
      GBNFTest.Demo-array ::= "\\"array\\"" ":" ws01 array  ::=
      "[" ws01 (
              string
          ("," ws01 string)*
      )? "]"

      GBNFTest.Demo-boolean ::= "\\"boolean\\"" ":" ws01 boolean
      GBNFTest.Demo-date ::= "\\"date\\"" ":" ws01 string
      GBNFTest.Demo-decimal ::= "\\"decimal\\"" ":" ws01 number
      GBNFTest.Demo-float ::= "\\"float\\"" ":" ws01 number
      GBNFTest.Demo-integer ::= "\\"integer\\"" ":" ws01 integer
      GBNFTest.Demo-map ::= "\\"map\\"" ":" ws01 object ::=
      "{" ws (
          string ":" ws string
          ("," ws string ":" ws string)*
      )? "}"

      GBNFTest.Demo-map-two ::= "\\"map_two\\"" ":" ws01 object ::=
      "{" ws (
          string ":" ws string
          ("," ws string ":" ws string)*
      )? "}"

      GBNFTest.Demo-naive-datetime ::= "\\"naive_datetime\\"" ":" ws01 string
      GBNFTest.Demo-naive-datetime-usec ::= "\\"naive_datetime_usec\\"" ":" ws01 string
      GBNFTest.Demo-string ::= "\\"string\\"" ":" ws01 string
      GBNFTest.Demo-time ::= "\\"time\\"" ":" ws01 string
      GBNFTest.Demo-time-usec ::= "\\"time_usec\\"" ":" ws01 string
      GBNFTest.Demo-utc-datetime ::= "\\"utc_datetime\\"" ":" ws01 string
      GBNFTest.Demo-utc-datetime-usec ::= "\\"utc_datetime_usec\\"" ":" ws01 string

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
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    assert gbnf == expected_gbnf
  end
end
