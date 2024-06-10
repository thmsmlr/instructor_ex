Code.compiler_options(ignore_module_conflict: true, docs: true, debug_info: true)

defmodule InstructorTest do
  use ExUnit.Case, async: false

  import Mox

  require Instructor.TestHelpers
  alias Instructor.TestHelpers

  setup :verify_on_exit!

  setup context do
    case Map.get(context, :adapter) do
      :llamacpp ->
        Application.put_env(:instructor, :adapter, Instructor.Adapters.Llamacpp)

      :openai ->
        Application.put_env(:instructor, :adapter, Instructor.Adapters.OpenAI)
        Application.put_env(:instructor, :openai, api_key: System.fetch_env!("OPENAI_API_KEY"))

      :openai_mock ->
        Application.put_env(:instructor, :adapter, InstructorTest.MockOpenAI)
    end
  end

  def mock_response(:openai_mock, mode, expected) do
    TestHelpers.mock_openai_response(mode, expected)
  end

  def mock_response(_, _, _), do: nil

  def mock_stream_response(:openai_mock, mode, expected) do
    TestHelpers.mock_openai_response_stream(mode, expected)
  end

  def mock_stream_response(_, _, _), do: nil

  for adapter <- [:openai_mock, :openai, :llamacpp] do
    # for adapter <- [:openai] do
    describe "#{inspect(adapter)}" do
      @tag adapter: adapter
      test "schemaless ecto" do
        expected = %{name: "George Washington", birth_date: ~D[1732-02-22]}
        mock_response(unquote(adapter), :tools, expected)

        result =
          Instructor.chat_completion(
            model: "gpt-3.5-turbo",
            response_model: %{name: :string, birth_date: :date},
            messages: [
              %{role: "user", content: "Who was the first president of the USA?"}
            ]
          )

        assert {:ok, %{name: name, birth_date: birth_date}, _usage} = result
        assert is_binary(name)
        assert %Date{} = birth_date
      end

      defmodule SpamPrediction do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          field(:class, Ecto.Enum, values: [:spam, :not_spam])
          field(:score, :float)
        end
      end

      @tag adapter: adapter
      test "basic ecto model" do
        expected = %{class: :spam, score: 0.9}
        mock_response(unquote(adapter), :tools, expected)

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

        assert {:ok, %SpamPrediction{class: :spam, score: score}, _usage} = result
        assert is_float(score)
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

      @tag adapter: adapter
      test "all ecto types" do
        expected = %{
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
        }

        mock_response(unquote(adapter), :tools, expected)

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

        assert {:ok,
                %AllEctoTypes{
                  binary_id: binary_id,
                  integer: integer,
                  float: float,
                  boolean: boolean,
                  string: string,
                  array: array,
                  map: map,
                  map_two: map_two,
                  decimal: decimal,
                  date: date,
                  time: time,
                  time_usec: time_usec,
                  naive_datetime: naive_datetime,
                  naive_datetime_usec: naive_datetime_usec,
                  utc_datetime: utc_datetime,
                  utc_datetime_usec: utc_datetime_usec
                }, _usage} = result

        assert is_binary(binary_id)
        assert is_integer(integer)
        assert is_float(float)
        assert is_boolean(boolean)
        assert is_binary(string)
        assert is_list(array)
        assert is_map(map)
        assert is_map(map_two)
        assert %Decimal{} = decimal
        assert %Date{} = date
        assert %Time{} = time
        assert %Time{} = time_usec
        assert %NaiveDateTime{} = naive_datetime
        assert %NaiveDateTime{} = naive_datetime_usec
        assert %DateTime{} = utc_datetime
        assert %DateTime{} = utc_datetime_usec
      end

      defmodule President do
        use Ecto.Schema

        @primary_key false
        embedded_schema do
          field(:name, :string)
          field(:birthdate, :date)
        end
      end

      @tag adapter: adapter
      test "streams arrays one at a time" do
        presidents = [
          %{name: "George Washington", birthdate: ~D[1732-02-22]},
          %{name: "John Adams", birthdate: ~D[1735-10-30]},
          %{name: "Thomas Jefferson", birthdate: ~D[1743-04-13]}
        ]

        mock_stream_response(unquote(adapter), :tools, presidents)

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
                 {:ok, %{name: "George Washington", birthdate: %Date{}}},
                 {:ok, %{name: "John Adams", birthdate: %Date{}}},
                 {:ok, %{name: "Thomas Jefferson", birthdate: %Date{}}}
               ] = Enum.to_list(result)
      end

      @tag adapter: adapter
      test "stream partial object" do
        president = %{name: "George Washington", birthdate: ~D[1732-02-22]}

        mock_stream_response(unquote(adapter), :tools, president)

        result =
          Instructor.chat_completion(
            model: "gpt-3.5-turbo",
            stream: true,
            response_model: {:partial, President},
            messages: [
              %{role: "user", content: "Who was the first president of the United States"}
            ]
          )

        assert TestHelpers.is_stream?(result)

        result = Enum.to_list(result)
        [first, second, third, last] = result |> Enum.uniq()

        assert {:partial, %President{}} = first

        assert match?({:partial, %President{name: "George Washington"}}, second) or
                 match?({:partial, %President{birthdate: %Date{}}}, second)

        assert match?({:partial, %President{name: "George Washington"}}, third) or
                 match?({:partial, %President{birthdate: %Date{}}}, third)

        assert {:ok, %President{name: "George Washington", birthdate: %Date{}}} = last
      end

      @tag adapter: adapter
      test "stream partial array of objects" do
        presidents = [
          %{name: "George Washington", birthdate: ~D[1732-02-22]},
          %{name: "John Adams", birthdate: ~D[1735-10-30]}
        ]

        mock_stream_response(unquote(adapter), :tools, presidents)

        result =
          Instructor.chat_completion(
            model: "gpt-3.5-turbo",
            stream: true,
            response_model: {:partial, {:array, President}},
            messages: [
              %{role: "user", content: "Who were the first 2 presidents of the United States"}
            ]
          )

        assert TestHelpers.is_stream?(result)

        result = Enum.filter(result, &(length(&1) > 0)) |> Enum.uniq()

        [first, second, third, fourth, fifth, sixth, seventh] = result |> Enum.uniq()

        assert [partial: %President{}] = first
        assert [partial: %President{}] = second
        assert [partial: %President{}] = third
        assert [ok: %President{}, partial: %President{}] = fourth
        assert [ok: %President{}, partial: %President{}] = fifth
        assert [ok: %President{}, partial: %President{}] = sixth
        assert [ok: %President{}, ok: %President{}] = seventh
      end
    end
  end

  defmodule QuestionAnswer do
    use Ecto.Schema
    use Instructor.Validator

    @primary_key false
    embedded_schema do
      field(:question, :string)
      field(:answer, :string)
    end

    @impl true
    def validate_changeset(changeset) do
      changeset
      |> validate_with_llm(:answer, "do not say anything objectionable")
    end
  end

  @tag adapter: :openai_mock
  test "llm validator" do
    TestHelpers.mock_openai_response(:tools, %{
      question: "What is the meaning of life?",
      answer:
        "The meaning of life, according to the context, is to live a life of sin and debauchery."
    })

    TestHelpers.mock_openai_response(:tools, %{
      valid?: false,
      reason: "The statement promotes sin and debauchery, which is objectionable."
    })

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        response_model: QuestionAnswer,
        messages: [
          %{
            role: "user",
            content: "What is the meaning of life?"
          }
        ]
      )

    assert {:error, %Ecto.Changeset{valid?: false}} = result
  end

  @tag adapter: :openai_mock
  test "retry upto n times" do
    TestHelpers.mock_openai_response(:tools, %{wrong_field: "foobar"})
    TestHelpers.mock_openai_response(:tools, %{wrong_field: "foobar"})

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

    TestHelpers.mock_openai_response(:tools, %{wrong_field: "foobar"})
    TestHelpers.mock_openai_response(:tools, %{field: 123})
    TestHelpers.mock_openai_response(:tools, %{field: "foobar"})

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        max_retries: 3,
        response_model: %{field: :string},
        messages: [
          %{role: "user", content: "What is the field?"}
        ]
      )

    assert {:ok, %{field: "foobar"}, _usage} = result
  end

  for mode <- [:tools, :json, :md_json] do
    @tag adapter: :openai_mock
    test "handles #{mode}" do
      mode = unquote(mode)
      TestHelpers.mock_openai_response(mode, %{name: "Thomas"})

      result =
        Instructor.chat_completion(
          model: "gpt-3.5-turbo",
          mode: mode,
          response_model: %{name: :string},
          messages: [
            %{role: "user", content: "What's my name?"}
          ]
        )

      assert {:ok, %{name: "Thomas"}, _usage} = result
    end

    @tag adapter: :openai_mock
    test "handles streaming #{mode}" do
      mode = unquote(mode)

      TestHelpers.mock_openai_response_stream(mode, [
        %{name: "Thomas"},
        %{name: "Jason"}
      ])

      result =
        Instructor.chat_completion(
          model: "gpt-3.5-turbo",
          mode: mode,
          stream: true,
          response_model: {:array, %{name: :string}},
          messages: [
            %{role: "user", content: "Repeat after me: Thomas, Jason"}
          ]
        )

      assert [ok: %{name: "Thomas"}, ok: %{name: "Jason"}] =
               result |> Enum.to_list()
    end
  end
end
