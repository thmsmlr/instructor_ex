defmodule Instructor.SSEStreamParserTest do
  use ExUnit.Case

  alias Instructor.SSEStreamParser

  test "parses a stream" do
    tokens = [
      "data: { \"number\": 1 }\n",
      "data: { \"number\": 2 }\n",
      "data: { \"number\": 3 }\n"
    ]

    assert SSEStreamParser.parse(tokens) |> Enum.to_list() == [
             %{"number" => 1},
             %{"number" => 2},
             %{"number" => 3}
           ]
  end

  test "parses a stream where lines are split across chunks" do
    tokens = [
      "data: { \"number\": 1 }\n",
      "data: { \"number\":",
      " 2 }\n",
      "data: { \"number\": 3 }\n"
    ]

    assert SSEStreamParser.parse(tokens) |> Enum.to_list() == [
             %{"number" => 1},
             %{"number" => 2},
             %{"number" => 3}
           ]
  end

  test "handles errors returned from the stream" do
    tokens = [
      "{\n  \"error\": {\n    \"message\": \"Invalid schema for function",
      " 'Schema': In context=('properties', 'value', 'items', 'properties', 'value', 'type', '4')",
      ", array schema missing items.\",\n    \"type\": \"invalid_request_error\",\n",
      "    \"param\": \"tools[0].function.parameters\",\n    \"code\": \"invalid_function_parameters\"\n  }\n}\n"
    ]

    assert_raise RuntimeError,
                 ~r/{.*"error".*"message".*"Invalid schema for function.*}/,
                 fn ->
                   SSEStreamParser.parse(tokens) |> Enum.to_list()
                 end
  end
end
