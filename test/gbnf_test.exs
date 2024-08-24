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
        root ::=  "{" ws01 root-array--prop "," ws01 root-boolean--prop "," ws01 root-date--prop "," ws01 root-decimal--prop "," ws01 root-float--prop "," ws01 root-integer--prop "," ws01 root-map--prop "," ws01 root-map-two--prop "," ws01 root-naive-datetime--prop "," ws01 root-naive-datetime-usec--prop "," ws01 root-string--prop "," ws01 root-time--prop "," ws01 root-time-usec--prop "," ws01 root-utc-datetime--prop "," ws01 root-utc-datetime-usec--prop "}" ws01
        root-array--prop ::= "\\"array\\"" ":" ws01 root-array
        root-array ::=
        "[" ws01 (
                string
            ("," ws01 string)*
        )? "]"

        root-boolean--prop ::= "\\"boolean\\"" ":" ws01 boolean
        root-date--prop ::= "\\"date\\"" ":" ws01 date
        root-decimal--prop ::= "\\"decimal\\"" ":" ws01 number
        root-float--prop ::= "\\"float\\"" ":" ws01 number
        root-integer--prop ::= "\\"integer\\"" ":" ws01 integer
        root-map--prop ::= "\\"map\\"" ":" ws01 root-map
        root-map ::=
        "{" ws (
            string ":" ws value
            ("," ws string ":" ws value)*
        )? "}"

        root-map-two--prop ::= "\\"map_two\\"" ":" ws01 root-map-two
        root-map-two ::=
        "{" ws (
            string ":" ws string
            ("," ws string ":" ws string)*
        )? "}"

        root-naive-datetime--prop ::= "\\"naive_datetime\\"" ":" ws01 datetime
        root-naive-datetime-usec--prop ::= "\\"naive_datetime_usec\\"" ":" ws01 datetime
        root-string--prop ::= "\\"string\\"" ":" ws01 string
        root-time--prop ::= "\\"time\\"" ":" ws01 time
        root-time-usec--prop ::= "\\"time_usec\\"" ":" ws01 time-usec
        root-utc-datetime--prop ::= "\\"utc_datetime\\"" ":" ws01 datetime
        root-utc-datetime-usec--prop ::= "\\"utc_datetime_usec\\"" ":" ws01 datetime

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
        date--val ::= [0-9][0-9][0-9][0-9] "-" [0-9][0-9] "-" [0-9][0-9]
        datetime--val ::= date--val "T" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] ("." [0-9]+)? ("Z" | ("+" | "-") [0-9][0-9] ":" [0-9][0-9])
        date ::= "\\"" date--val "\\""
        datetime ::= "\\"" datetime--val "\\""

        time ::= "\\"" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] "\\""
        time-usec ::= "\\"" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] "." [0-9][0-9][0-9][0-9][0-9][0-9] "\\""

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

  test "nested inline objects" do
    ecto_schema = %{
      value:
        Ecto.ParameterizedType.init(Ecto.Embedded,
          cardinality: :one,
          related: %{name: :string, birth_date: :date}
        )
    }

    gbnf =
      ecto_schema
      |> JSONSchema.from_ecto_schema()
      |> GBNF.from_json_schema()
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    expected_gbnf =
      """
        root ::=  "{" ws01 root-value--prop "}" ws01
        root-value--prop ::= "\\"value\\"" ":" ws01 root-value
        root-value ::= "{" ws01 root-value-birth-date--prop "," ws01 root-value-name--prop "}" ws01
        root-value-birth-date--prop ::= "\\"birth_date\\"" ":" ws01 date
        root-value-name--prop ::= "\\"name\\"" ":" ws01 string

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
        date--val ::= [0-9][0-9][0-9][0-9] "-" [0-9][0-9] "-" [0-9][0-9]
        datetime--val ::= date--val "T" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] ("." [0-9]+)? ("Z" | ("+" | "-") [0-9][0-9] ":" [0-9][0-9])
        date ::= "\\"" date--val "\\""
        datetime ::= "\\"" datetime--val "\\""

        time ::= "\\"" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] "\\""
        time-usec ::= "\\"" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] "." [0-9][0-9][0-9][0-9][0-9][0-9] "\\""

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

  test "sanitizes schema names" do
    defmodule Parent do
      use Ecto.Schema

      @primary_key false
      embedded_schema do
        embeds_one :value, Child, primary_key: false do
          field(:name, :string)
        end
      end
    end

    gbnf =
      Parent
      |> JSONSchema.from_ecto_schema()
      |> GBNF.from_json_schema()
      |> String.trim()
      |> String.replace(~r/\s+/, " ")

    expected_gbnf =
      """
        root ::=  "{" ws01 root-value--prop "}" ws01
        root-value--prop ::= "\\"value\\"" ":" ws01 GBNFTest-Parent-Child
        GBNFTest-Parent-Child ::= "{" ws01 GBNFTest-Parent-Child-name--prop "}" ws01
        GBNFTest-Parent-Child-name--prop ::= "\\"name\\"" ":" ws01 string

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
        date--val ::= [0-9][0-9][0-9][0-9] "-" [0-9][0-9] "-" [0-9][0-9]
        datetime--val ::= date--val "T" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] ("." [0-9]+)? ("Z" | ("+" | "-") [0-9][0-9] ":" [0-9][0-9])
        date ::= "\\"" date--val "\\""
        datetime ::= "\\"" datetime--val "\\""

        time ::= "\\"" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] "\\""
        time-usec ::= "\\"" [0-9][0-9] ":" [0-9][0-9] ":" [0-9][0-9] "." [0-9][0-9][0-9][0-9][0-9][0-9] "\\""

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
