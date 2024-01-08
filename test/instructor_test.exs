defmodule InstructorTest do
  use ExUnit.Case, async: true

  import Mox

  require Instructor.TestHelpers
  alias Instructor.TestHelpers

  setup :verify_on_exit!

  test "schemaless ecto" do
    expected = %{name: "George Washington", birth_date: ~D[1732-02-22]}
    TestHelpers.mock_openai_response(expected)

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        response_model: %{name: :string, birth_date: :date},
        messages: [
          %{role: "user", content: "Who was the first president of the USA?"}
        ]
      )

    assert {:ok, ^expected} = result
  end

  defmodule SpamPrediction do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:class, Ecto.Enum, values: [:spam, :not_spam])
      field(:score, :float)
    end
  end

  test "basic ecto model" do
    TestHelpers.mock_openai_response(%{class: :spam, score: 0.9})

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        response_model: SpamPrediction,
        messages: [
          %{
            role: "user",
            content:
              "Classify the following text: Hello, I am a Nigerian prince and I would like to give you $1,000,000."
          }
        ]
      )

    assert {:ok, %SpamPrediction{class: :spam, score: 0.9}} = result
  end

  defmodule AllEctoTypes do
    use Ecto.Schema

    # Be explicit about all fields in this test
    @primary_key false
    embedded_schema do
      field(:binary_id, :binary_id)
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

  test "all ecto types" do
    TestHelpers.mock_openai_response(%{
      binary_id: "binary_id",
      integer: 1,
      float: 1.0,
      boolean: true,
      string: "string",
      array: ["array"],
      map: %{"map" => "map"},
      map_two: %{"map_two" => "map_two"},
      decimal: 1.0,
      date: "2021-08-01",
      time: "12:00:00",
      time_usec: "12:00:00.000000",
      naive_datetime: "2021-08-01T12:00:00",
      naive_datetime_usec: "2021-08-01T12:00:00.000000",
      utc_datetime: "2021-08-01T12:00:00Z",
      utc_datetime_usec: "2021-08-01T12:00:00.000000Z"
    })

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        response_model: AllEctoTypes,
        messages: [
          %{
            role: "user",
            content:
              "What are the types of the following fields: binary_id, integer, float, boolean, string, array, map, map_two, decimal, date, time, time_usec, naive_datetime, naive_datetime_usec, utc_datetime, utc_datetime_usec?"
          }
        ]
      )

    decimal = Decimal.new("1.0")

    assert {:ok,
            %AllEctoTypes{
              binary_id: "binary_id",
              integer: 1,
              float: 1.0,
              boolean: true,
              string: "string",
              array: ["array"],
              map: %{"map" => "map"},
              map_two: %{"map_two" => "map_two"},
              decimal: ^decimal,
              date: ~D[2021-08-01],
              time: ~T[12:00:00],
              time_usec: ~T[12:00:00.000000],
              naive_datetime: ~N[2021-08-01 12:00:00],
              naive_datetime_usec: ~N[2021-08-01 12:00:00.000000],
              utc_datetime: ~U[2021-08-01 12:00:00Z],
              utc_datetime_usec: ~U[2021-08-01 12:00:00.000000Z]
            }} = result
  end

  test "retry upto n times" do
    TestHelpers.mock_openai_response(%{wrong_field: "foobar"})
    TestHelpers.mock_openai_response(%{wrong_field: "foobar"})

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        max_retries: 1,
        response_model: %{field: :string},
        messages: [
          %{role: "user", content: "What is the field?"}
        ]
      )

    assert {:error, %Ecto.Changeset{valid?: false}} = result

    TestHelpers.mock_openai_response(%{wrong_field: "foobar"})
    TestHelpers.mock_openai_response(%{field: 123})
    TestHelpers.mock_openai_response(%{field: "foobar"})

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        max_retries: 3,
        response_model: %{field: :string},
        messages: [
          %{role: "user", content: "What is the field?"}
        ]
      )

    assert {:ok, %{field: "foobar"}} = result
  end

  defmodule President do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field(:name, :string)
    end
  end

  test "streams arrays one at a time" do
    presidents = [
      %{name: "George Washington"},
      %{name: "John Adams"},
      %{name: "Thomas Jefferson"}
    ]

    TestHelpers.mock_openai_response_stream(presidents)

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        stream: true,
        response_model: {:array, President},
        messages: [
          %{role: "user", content: "What are the first 3 presidents of the United States?"}
        ]
      )

    assert TestHelpers.is_stream?(result)

    assert [
             {:ok, %{name: "George Washington"}},
             {:ok, %{name: "John Adams"}},
             {:ok, %{name: "Thomas Jefferson"}}
           ] = Enum.to_list(result)
  end
end
