defmodule Instructor.TestHelpers do
  import Mox

  def mock_openai_response(:tools, result) do
    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      {:ok,
       %{
         "id" => "chatcmpl-8e9AVo9NHfvBG5cdtAEiJMm7q4Htz",
         "usage" => %{
           "completion_tokens" => 23,
           "prompt_tokens" => 136,
           "total_tokens" => 159
         },
         "choices" => [
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
                     "arguments" => Jason.encode!(result),
                     "name" => "schema"
                   },
                   "id" => "call_DT9fBvVCHWGSf9IeFZnlarIY",
                   "type" => "function"
                 }
               ]
             }
           }
         ],
         "model" => "gpt-3.5-turbo-0613",
         "object" => "chat.completion",
         "created" => 1_704_579_055,
         "system_fingerprint" => nil
       }, result}
    end)
  end

  def mock_openai_response(mode, result) when mode in [:json, :md_json] do
    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      {
        :ok,
        %{
          "id" => "chatcmpl-8e9AVo9NHfvBG5cdtAEiJMm7q4Htz",
          "usage" => %{
            "completion_tokens" => 23,
            "prompt_tokens" => 136,
            "total_tokens" => 159
          },
          "choices" => [
            %{
              "finish_reason" => "stop",
              "index" => 0,
              "logprobs" => nil,
              "message" => %{
                "content" => Jason.encode!(result),
                "role" => "assistant"
              }
            }
          ],
          "model" => "gpt-3.5-turbo-0613",
          "object" => "chat.completion",
          "created" => 1_704_579_055,
          "system_fingerprint" => nil
        },
        result
      }
    end)
  end

  def mock_openai_response_stream(:tools, result) do
    chunks =
      Jason.encode!(%{value: result})
      |> String.graphemes()
      |> Enum.chunk_every(12)
      |> Enum.map(fn chunk ->
        Enum.join(chunk, "")
      end)

    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      chunks
    end)
  end

  def mock_openai_response_stream(mode, result) when mode in [:json, :md_json] do
    chunks =
      Jason.encode!(%{value: result})
      |> String.graphemes()
      |> Enum.chunk_every(12)
      |> Enum.map(fn chunk ->
        Enum.join(chunk, "")
      end)

    InstructorTest.MockOpenAI
    |> expect(:chat_completion, fn _params, _config ->
      chunks
    end)
  end

  def mock_openai_reask_messages() do
    InstructorTest.MockOpenAI
    |> expect(:reask_messages, fn _raw_response, _params, _config ->
      []
    end)
  end

  def is_stream?(variable) do
    case variable do
      %Stream{} ->
        true

      _ when is_function(variable, 0) or is_function(variable, 1) or is_function(variable, 2) ->
        true

      _ ->
        false
    end
  end
end
