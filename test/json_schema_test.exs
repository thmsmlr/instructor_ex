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
        "$defs" => %{
          "JSONSchemaTest.Demo" => %{
            "description" => nil,
            "properties" => %{
              "string" => %{"title" => "string", "type" => "string"}
            },
            "required" => ["string"],
            "title" => "JSONSchemaTest.Demo",
            "type" => "object"
          }
        },
        "allOf" => [%{"$ref" => "#/$defs/JSONSchemaTest.Demo"}]
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
      "$defs" => %{
        "JSONSchemaTest.Demo" => %{
          "description" => nil,
          "properties" => %{
            "string" => %{"title" => "string", "type" => "string"}
          },
          "required" => ["string"],
          "title" => "JSONSchemaTest.Demo",
          "type" => "object"
        }
      },
      "allOf" => [%{"$ref" => "#/$defs/JSONSchemaTest.Demo"}]
    }

    assert json_schema == expected_json_schema
  end

  test "includes documentation" do
    json_schema =
      JSONSchema.from_ecto_schema(InstructorTest.DemoWithDocumentation)
      |> Jason.decode!()

    expected_json_schema =
      %{
        "$defs" => %{
          "InstructorTest.DemoWithDocumentation" => %{
            "description" => "Hello world\n",
            "properties" => %{"string" => %{"title" => "string", "type" => "string"}},
            "required" => ["string"],
            "title" => "InstructorTest.DemoWithDocumentation",
            "type" => "object"
          }
        },
        "allOf" => [%{"$ref" => "#/$defs/InstructorTest.DemoWithDocumentation"}]
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
      "$defs" => %{
        "JSONSchemaTest.Demo" => %{
          "description" => nil,
          "properties" => %{
            "array" => %{"items" => %{"type" => "string"}, "title" => "array", "type" => "array"},
            "boolean" => %{"title" => "boolean", "type" => "boolean"},
            "date" => %{"title" => "date", "type" => "string"},
            "decimal" => %{"format" => "float", "title" => "decimal", "type" => "number"},
            "float" => %{"format" => "float", "title" => "float", "type" => "number"},
            "integer" => %{"title" => "integer", "type" => "integer"},
            "map" => %{
              "additionalProperties" => %{"type" => "string"},
              "title" => "map",
              "type" => "object"
            },
            "map_two" => %{
              "additionalProperties" => %{"type" => "string"},
              "title" => "map_two",
              "type" => "object"
            },
            "naive_datetime" => %{"title" => "naive_datetime", "type" => "string"},
            "naive_datetime_usec" => %{"title" => "naive_datetime_usec", "type" => "string"},
            "string" => %{"title" => "string", "type" => "string"},
            "time" => %{"title" => "time", "type" => "string"},
            "time_usec" => %{"title" => "time_usec", "type" => "string"},
            "utc_datetime" => %{"title" => "utc_datetime", "type" => "string"},
            "utc_datetime_usec" => %{"title" => "utc_datetime_usec", "type" => "string"}
          },
          "required" => [
            "integer",
            "date",
            "float",
            "time",
            "string",
            "map",
            "boolean",
            "array",
            "decimal",
            "map_two",
            "time_usec",
            "naive_datetime",
            "naive_datetime_usec",
            "utc_datetime",
            "utc_datetime_usec"
          ],
          "title" => "JSONSchemaTest.Demo",
          "type" => "object"
        }
      },
      "allOf" => [%{"$ref" => "#/$defs/JSONSchemaTest.Demo"}]
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
        "JSONSchemaTest.Demo" => %{
          "description" => nil,
          "properties" => %{
            "embedded" => %{
              "items" => %{"$ref" => "#/$defs/JSONSchemaTest.Embedded"},
              "title" => "JSONSchemaTest.Embedded",
              "type" => "array"
            }
          },
          "required" => ["embedded"],
          "title" => "JSONSchemaTest.Demo",
          "type" => "object"
        },
        "JSONSchemaTest.Embedded" => %{
          "description" => nil,
          "properties" => %{
            "string" => %{"title" => "string", "type" => "string"}
          },
          "required" => ["string"],
          "title" => "JSONSchemaTest.Embedded",
          "type" => "object"
        }
      },
      "allOf" => [%{"$ref" => "#/$defs/JSONSchemaTest.Demo"}]
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

    expected_json_schema = %{
      "$defs" => %{
        "JSONSchemaTest.Demo" => %{
          "description" => nil,
          "properties" => %{
            "id" => %{"title" => "id", "type" => "integer"},
            "child" => %{"$ref" => "#/$defs/JSONSchemaTest.Child"}
          },
          "required" => ["id", "child"],
          "title" => "JSONSchemaTest.Demo",
          "type" => "object"
        },
        "JSONSchemaTest.Child" => %{
          "description" => nil,
          "properties" => %{
            "id" => %{"title" => "id", "type" => "integer"},
            "string" => %{"title" => "string", "type" => "string"}
          },
          "required" => ["id", "string"],
          "title" => "JSONSchemaTest.Child",
          "type" => "object"
        }
      },
      "allOf" => [%{"$ref" => "#/$defs/JSONSchemaTest.Demo"}]
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
        "JSONSchemaTest.Demo" => %{
          "description" => nil,
          "properties" => %{
            "id" => %{"title" => "id", "type" => "integer"},
            "children" => %{
              "items" => %{"$ref" => "#/$defs/JSONSchemaTest.Child"},
              "title" => "JSONSchemaTest.Child",
              "type" => "array"
            }
          },
          "required" => ["id", "children"],
          "title" => "JSONSchemaTest.Demo",
          "type" => "object"
        },
        "JSONSchemaTest.Child" => %{
          "description" => nil,
          "properties" => %{
            "id" => %{"title" => "id", "type" => "integer"},
            "string" => %{"title" => "string", "type" => "string"}
          },
          "required" => ["id", "string"],
          "title" => "JSONSchemaTest.Child",
          "type" => "object"
        }
      },
      "allOf" => [%{"$ref" => "#/$defs/JSONSchemaTest.Demo"}]
    }

    assert json_schema == expected_json_schema
  end
end
