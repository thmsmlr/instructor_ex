defmodule Instructor.TestHelpers do
  defmacro mock_openai_response(result) do
    quote do
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
                       "arguments" => Jason.encode!(unquote(result)),
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
    end
  end
end
