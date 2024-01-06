defmodule InstructorTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  test "schemaless ecto" do
    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn params ->
      {:ok,
       %{
         id: "chatcmpl-8e9AVo9NHfvBG5cdtAEiJMm7q4Htz",
         usage: %{
           "completion_tokens" => 23,
           "prompt_tokens" => 136,
           "total_tokens" => 159
         },
         choices: [
           %{
             "finish_reason" => "stop",
             "index" => 0,
             "logprobs" => nil,
             "message" => %{
               "content" => nil,
               "role" => "assistant",
               "tool_calls" => [
                 %{
                   "function" => %{
                     "arguments" =>
                       "{\n  \"name\": \"George Washington\",\n  \"birth_date\": \"1732-02-22\"\n}",
                     "name" => "schema"
                   },
                   "id" => "call_DT9fBvVCHWGSf9IeFZnlarIY",
                   "type" => "function"
                 }
               ]
             }
           }
         ],
         model: "gpt-3.5-turbo-0613",
         object: "chat.completion",
         created: 1_704_579_055,
         system_fingerprint: nil
       }}
    end)

    result =
      Instructor.chat_completion(
        model: "gpt-3.5-turbo",
        response_model: %{name: :string, birth_date: :date},
        messages: [
          %{role: "user", content: "Who was the first president of the USA?"}
        ]
      )

    assert {:ok, %{name: "George Washington", birth_date: ~D[1732-02-22]}} = result
  end
end
