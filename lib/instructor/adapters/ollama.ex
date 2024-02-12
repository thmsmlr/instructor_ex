defmodule Instructor.Adapters.Ollama do
  @moduledoc """

  """
  @behaviour Instructor.Adapter

  @receive_timeout 60_000

  alias Instructor.JSONSchema

  @impl Instructor.Adapter
  def chat_completion(params, _config \\ nil) do
    {response_model, _} = Keyword.pop!(params, :response_model)

    # prompt = apply_chat_template(:ollama, json_schema, messages)
    stream = Keyword.get(params, :stream, false)

    params = Map.new(params)
    params |> IO.inspect(label: "params are: ")

    if stream do
      do_streaming_chat_completion(params)
    else
      IO.inspect(params, label: " not stream params ")
      do_chat_completion(params)
    end
  end

  defp do_streaming_chat_completion(mode_params) do
    {pid, ref} = {self(), make_ref()}

    Stream.resource(
      fn ->
        Task.async(fn ->
          IO.inspect("making request now")

          Req.post!("http://localhost:11434/v1/chat/completions",
            json: mode_params,
            receive_timeout: @receive_timeout,
            into: fn {:data, data}, {req, resp} ->
              send(pid, {ref, data})
              {:cont, {req, resp}}
            end
          )

          send(pid, {ref, :done})
        end)
      end,
      fn acc ->
        receive do
          {^ref, :done} ->
            {:halt, acc}

          {^ref, "data: " <> data} ->
            data = Jason.decode!(data)
            {[data], acc}
            # after
            #   @receive_timeout -> :request_timeout
        end
      end,
      fn acc -> acc end
    )
    |> Stream.map(fn %{"content" => chunk} ->
      to_openai_streaming_response(chunk)
    end)
  end

  defp to_openai_streaming_response(chunk) when is_binary(chunk) do
    %{
      "choices" => [
        %{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => chunk}}]}}
      ]
    }
  end

  defp do_chat_completion(mode_params) do
    response =
      Req.post!("http://localhost:11434/v1/chat/completions",
        json: mode_params,
        receive_timeout: 60_000
      )

    case response do
      %{status: 200, body: params} ->
        {:ok, to_openai_response(params)}

      _ ->
        nil
    end
  end

  defp to_openai_response(params) do
    %{
      "choices" => [
        %{
          "message" => %{
            "content" => _content
          }
        }
      ]
    } = params

    IO.inspect(params, label: "jason decoded content")
    params
  end
end
