Code.compiler_options(ignore_module_conflict: true, docs: true, debug_info: true)

defmodule JSONSchemaTest do
  use ExUnit.Case, async: true

  alias Instructor.JSONSchema

  test "schema" do
    defmodule Demo do
      use Ecto.Schema

      @primary_key false
      schema "demo" do
        field(:string, :string)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(JSONSchemaTest.Demo)
      |> Jason.decode!()

    expected_json_schema =
      %{
        "description" => "",
        "properties" => %{
          "string" => %{"title" => "string", "type" => "string"}
        },
        "required" => ["string"],
        "title" => "JSONSchemaTest.Demo",
        "type" => "object"
      }

    assert json_schema == expected_json_schema
  end

  test "embedded_schema" do
    defmodule Demo do
      use Ecto.Schema

      @primary_key false
      embedded_schema do
        field(:string, :string)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> Jason.decode!()

    expected_json_schema = %{
      "description" => "",
      "properties" => %{"string" => %{"title" => "string", "type" => "string"}},
      "required" => ["string"],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object"
    }

    assert json_schema == expected_json_schema
  end

  test "includes documentation" do
    json_schema =
      JSONSchema.from_ecto_schema(InstructorTest.DemoWithDocumentation)
      |> Jason.decode!()

    expected_json_schema =
      %{
        "description" => "Hello world\n",
        "properties" => %{"string" => %{"title" => "string", "type" => "string"}},
        "required" => ["string"],
        "title" => "InstructorTest.DemoWithDocumentation",
        "type" => "object"
      }

    assert json_schema == expected_json_schema
  end

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

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> Jason.decode!()

    expected_json_schema = %{
      "description" => "",
      "properties" => %{
        "array" => %{"items" => %{"type" => "string"}, "title" => "array", "type" => "array"},
        "boolean" => %{"title" => "boolean", "type" => "boolean"},
        "date" => %{"title" => "date", "type" => "string", "format" => "date"},
        "decimal" => %{"format" => "float", "title" => "decimal", "type" => "number"},
        "float" => %{"format" => "float", "title" => "float", "type" => "number"},
        "integer" => %{"title" => "integer", "type" => "integer"},
        "map" => %{
          "additionalProperties" => %{},
          "title" => "map",
          "type" => "object"
        },
        "map_two" => %{
          "additionalProperties" => %{"type" => "string"},
          "title" => "map_two",
          "type" => "object"
        },
        "naive_datetime" => %{
          "title" => "naive_datetime",
          "type" => "string",
          "format" => "date-time"
        },
        "naive_datetime_usec" => %{
          "title" => "naive_datetime_usec",
          "type" => "string",
          "format" => "date-time"
        },
        "string" => %{"title" => "string", "type" => "string"},
        "time" => %{
          "title" => "time",
          "type" => "string",
          "pattern" => "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}$"
        },
        "time_usec" => %{
          "title" => "time_usec",
          "type" => "string",
          "pattern" => "^[0-9]{2}:?[0-9]{2}:?[0-9]{2}.[0-9]{6}$"
        },
        "utc_datetime" => %{
          "title" => "utc_datetime",
          "type" => "string",
          "format" => "date-time"
        },
        "utc_datetime_usec" => %{
          "title" => "utc_datetime_usec",
          "type" => "string",
          "format" => "date-time"
        }
      },
      "required" => [
        "array",
        "boolean",
        "date",
        "decimal",
        "float",
        "integer",
        "map",
        "map_two",
        "naive_datetime",
        "naive_datetime_usec",
        "string",
        "time",
        "time_usec",
        "utc_datetime",
        "utc_datetime_usec"
      ],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object"
    }

    assert json_schema == expected_json_schema
  end

  test "embedded schemas" do
    defmodule Embedded do
      use Ecto.Schema

      @primary_key false
      embedded_schema do
        field(:string, :string)
      end
    end

    defmodule Demo do
      use Ecto.Schema

      @primary_key false
      embedded_schema do
        embeds_one(:embedded, Embedded)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> Jason.decode!()

    expected_json_schema = %{
      "$defs" => %{
        "JSONSchemaTest.Embedded" => %{
          "description" => "",
          "properties" => %{"string" => %{"title" => "string", "type" => "string"}},
          "required" => ["string"],
          "title" => "JSONSchemaTest.Embedded",
          "type" => "object"
        }
      },
      "description" => "",
      "properties" => %{
        "embedded" => %{"$ref" => "#/$defs/JSONSchemaTest.Embedded", "title" => "embedded"}
      },
      "required" => ["embedded"],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object"
    }

    assert json_schema == expected_json_schema
  end

  test "has_one" do
    defmodule Child do
      use Ecto.Schema

      schema "child" do
        field(:string, :string)
      end
    end

    defmodule Demo do
      use Ecto.Schema

      schema "demo" do
        has_one(:child, Child)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> Jason.decode!()

    expected_json_schema =
      %{
        "$defs" => %{
          "JSONSchemaTest.Child" => %{
            "description" => "",
            "properties" => %{
              "id" => %{"title" => "id", "type" => "integer"},
              "string" => %{"title" => "string", "type" => "string"}
            },
            "required" => ["id", "string"],
            "title" => "JSONSchemaTest.Child",
            "type" => "object"
          }
        },
        "description" => "",
        "properties" => %{
          "child" => %{"$ref" => "#/$defs/JSONSchemaTest.Child"},
          "id" => %{"title" => "id", "type" => "integer"}
        },
        "required" => ["child", "id"],
        "title" => "JSONSchemaTest.Demo",
        "type" => "object"
      }

    assert json_schema == expected_json_schema
  end

  test "has_many" do
    defmodule Child do
      use Ecto.Schema

      schema "child" do
        field(:string, :string)
      end
    end

    defmodule Demo do
      use Ecto.Schema

      schema "demo" do
        has_many(:children, Child)
      end
    end

    json_schema =
      JSONSchema.from_ecto_schema(Demo)
      |> Jason.decode!()

    expected_json_schema = %{
      "$defs" => %{
        "JSONSchemaTest.Child" => %{
          "description" => "",
          "properties" => %{
            "id" => %{"title" => "id", "type" => "integer"},
            "string" => %{"title" => "string", "type" => "string"}
          },
          "required" => ["id", "string"],
          "title" => "JSONSchemaTest.Child",
          "type" => "object"
        }
      },
      "description" => "",
      "properties" => %{
        "children" => %{
          "items" => %{"$ref" => "#/$defs/JSONSchemaTest.Child"},
          "title" => "JSONSchemaTest.Child",
          "type" => "array"
        },
        "id" => %{"title" => "id", "type" => "integer"}
      },
      "required" => ["children", "id"],
      "title" => "JSONSchemaTest.Demo",
      "type" => "object"
    }

    assert json_schema == expected_json_schema
  end

  test "handles ecto types with embeds recursively" do
    schema = %{
      value:
        Ecto.ParameterizedType.init(Ecto.Embedded,
          cardinality: :one,
          related: %{
            name: :string,
            children:
              Ecto.ParameterizedType.init(Ecto.Embedded,
                cardinality: :many,
                related: %{name: :string}
              )
          }
        )
    }

    json_schema =
      JSONSchema.from_ecto_schema(schema)
      |> Jason.decode!()

    expected_json_schema = %{
      "properties" => %{
        "value" => %{
          "properties" => %{
            "name" => %{"type" => "string"},
            "children" => %{
              "items" => %{
                "properties" => %{"name" => %{"type" => "string"}},
                "required" => ["name"],
                "type" => "object"
              },
              "type" => "array"
            }
          },
          "required" => ["children", "name"],
          "type" => "object"
        }
      },
      "required" => ["value"],
      "type" => "object",
      "title" => "root"
    }

    assert json_schema == expected_json_schema
  end
end
