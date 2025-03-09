defmodule Instructor.Adapters.DeepSeek do
  @moduledoc """
  DeepSeek Adapter for Instructor.

  ## Configuration

  ```elixir
  config :instructor, adapter: Instructor.Adapters.DeepSeek, deepseek: [
    api_key: "your_api_key" # Will use DEEPSEEK_API_KEY environment variable if not provided
  ]
  ```

  or at runtime:

  ```elixir
  Instructor.chat_completion(..., [
    adapter: Instructor.Adapters.DeepSeek,
    api_key: "your_api_key" # Will use DEEPSEEK_API_KEY environment variable if not provided
  ])
  ```

  To get an DeepSeek API key, see [DeepSeek](https://platform.deepseek.com/api_keys).
  """

  @behaviour Instructor.Adapter
  alias Instructor.Adapters
  alias Instructor.SSEStreamParser

  @supported_modes [:json_schema]

  @impl true
  def chat_completion(params, user_config \\ nil) do
    config = config(user_config)

    # Peel off instructor only parameters
    {_, params} = Keyword.pop(params, :response_model)
    {_, params} = Keyword.pop(params, :validation_context)
    {_, params} = Keyword.pop(params, :max_retries)
    {mode, params} = Keyword.pop(params, :mode)
    stream = Keyword.get(params, :stream, false)
    params = Enum.into(params, %{})

    if mode not in @supported_modes do
      raise "Unsupported DeepSeek mode #{mode}. Supported modes: #{inspect(@supported_modes)}"
    end

    {messages, params} = Map.pop!(params, :messages)
    {system_instruction, contents} = format_messages(messages)

    params =
      if system_instruction != nil do
        Map.put(params, :systemInstruction, system_instruction)
      else
        params
      end

    params = Map.put(params, :contents, contents)

    {model_config_params, params} =
      Map.split(params, [:top_k, :top_p, :max_tokens, :temperature, :n, :stop])

    generation_config =
      model_config_params
      |> Enum.into(%{}, fn
        {:stop, stops} -> {"stopSequences", stops}
        {:n, n} -> {"candidateCount", n}
        {:max_tokens, max_tokens} -> {"maxOutputTokens", max_tokens}
        {other_key, value} -> {Atom.to_string(other_key) |> snake_to_camel(), value}
      end)

    params = Map.put(params, :generationConfig, generation_config)

    if stream do
      do_streaming_chat_completion(mode, params, config)
    else
      do_chat_completion(mode, params, config)
    end
  end

  defp format_messages(messages) do
    Enum.reduce(messages, {nil, []}, fn message, {system_instruction, acc} ->
      case message do
        %{role: "assistant", content: content} ->
          {system_instruction, acc ++ [%{role: "model", parts: [%{text: content}]}]}

        %{role: "user", content: content} ->
          {system_instruction, acc ++ [%{role: "user", parts: [%{text: content}]}]}

        %{role: "system", content: content} ->
          sys =
            case system_instruction do
              nil -> %{role: "system", parts: [%{text: content}]}
              %{parts: parts} -> %{role: "system", parts: parts ++ [%{text: content}]}
            end

          {sys, acc}

        _ ->
          {system_instruction, acc}
      end
    end)
  end

  defp do_streaming_chat_completion(mode, params, config) do
    pid = self()
    {model, params} = Map.pop!(params, :model)
    {_, params} = Map.pop!(params, :stream)

    openai_compatible_params = %{
      model: model,
      messages: convert_to_openai_messages(params),
      stream: true
    }

    openai_compatible_params =
      params
      |> Map.take([
        :temperature,
        :max_tokens,
        :top_p,
        :n,
        :stop,
        :frequency_penalty,
        :presence_penalty,
        :response_format,
        :logprobs,
        :top_logprobs
      ])
      |> Map.merge(openai_compatible_params)

    Stream.resource(
      fn ->
        Task.async(fn ->
          options = [
            url: url(config),
            headers: %{"Authorization" => "Bearer " <> api_key(config)},
            json: openai_compatible_params,
            into: fn {:data, data}, {req, resp} ->
              send(pid, data)
              {:cont, {req, resp}}
            end
          ]

          Req.post!(options)
          send(pid, :done)
        end)
      end,
      fn task ->
        receive do
          :done ->
            {:halt, task}

          data ->
            {[data], task}
        after
          15_000 ->
            {:halt, task}
        end
      end,
      fn task -> Task.await(task) end
    )
    |> SSEStreamParser.parse()
    |> Stream.map(fn chunk -> parse_stream_chunk_for_mode(mode, chunk) end)
  end

  defp do_chat_completion(mode, params, config) do
    {model, params} = Map.pop!(params, :model)

    openai_compatible_params = %{
      model: model,
      messages: convert_to_openai_messages(params),
      stream: false
    }

    openai_compatible_params =
      params
      |> Map.take([
        :temperature,
        :max_tokens,
        :top_p,
        :n,
        :stop,
        :frequency_penalty,
        :presence_penalty,
        :response_format,
        :logprobs,
        :top_logprobs
      ])
      |> Map.merge(openai_compatible_params)

    response =
      Req.new()
      |> Req.post(
        url: url(config),
        headers: %{"Authorization" => "Bearer " <> api_key(config)},
        json: openai_compatible_params
      )

    with {:ok, %Req.Response{status: 200, body: body} = response} <- response,
         {:ok, body} <- parse_response_for_mode(mode, body) do
      {:ok, response, body}
    else
      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Unexpected HTTP response code: #{status}\n#{inspect(body)}"}

      e ->
        e
    end
  end

  defp convert_to_openai_messages(params) do
    system_instruction = Map.get(params, :systemInstruction)
    contents = Map.get(params, :contents, [])

    messages =
      contents
      |> Enum.map(fn
        %{role: "model", parts: [%{text: content}]} ->
          %{role: "assistant", content: content}

        %{role: "user", parts: [%{text: content}]} ->
          %{role: "user", content: content}

        %{role: role, parts: [%{text: content}]} ->
          %{role: role, content: content}
      end)

    if system_instruction do
      [%{role: "system", content: extract_system_content(system_instruction)} | messages]
    else
      messages
    end
  end

  defp extract_system_content(%{parts: parts}) do
    parts
    |> Enum.map(fn %{text: text} -> text end)
    |> Enum.join("\n")
  end

  defp parse_response_for_mode(:json_schema, %{
         "choices" => [%{"message" => %{"content" => text}}]
       }) do
    Jason.decode(text)
  end

  defp parse_stream_chunk_for_mode(:json_schema, %{
         "choices" => [%{"delta" => %{"content" => chunk}}]
       }) do
    chunk
  end

  defp snake_to_camel(snake_case_string) do
    snake_case_string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn {word, index} ->
      if index == 0, do: String.downcase(word), else: String.capitalize(word)
    end)
    |> Enum.join("")
  end

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI

  defp url(config), do: api_url(config) <> "/chat/completions"
  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_key(config), do: Keyword.fetch!(config, :api_key)

  defp config(nil), do: config(Application.get_env(:instructor, :deepseek, []))

  defp config(base_config) do
    default_config = [
      api_url: "https://api.deepseek.com",
      api_key: System.get_env("DEEPSEEK_API_KEY"),
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
