defmodule Instructor.SSEStreamParserTest do
  use ExUnit.Case

  alias Instructor.SSEStreamParser

  test "parses a stream" do
    tokens = [
      "data: { \"number\": 1 }\n",
      "data: { \"number\": 2 }\n",
      "data: { \"number\": 3 }\n",
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
      "data: { \"number\": 3 }\n",
    ]

    assert SSEStreamParser.parse(tokens) |> Enum.to_list() == [
      %{"number" => 1},
      %{"number" => 2},
      %{"number" => 3}
    ]
  end
end
