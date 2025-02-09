defmodule Instructor.Adapters.Gemini do
  @moduledoc """
  Adapter for Google Gemini.

  ## Configuration

  ```elixir
  config :instructor, adapter: Instructor.Adapters.Gemini, gemini: [
    api_key: "your_api_key" # Will use GOOGLE_API_KEY environment variable if not provided
  ]
  ```

  or at runtime:

  ```elixir
  Instructor.chat_completion(..., [
    adapter: Instructor.Adapters.Gemini,
    api_key: "your_api_key" # Will use GOOGLE_API_KEY environment variable if not provided
  ])
  ```

  To get a Google API key, see [Google AI Studio](https://aistudio.google.com/apikey).
  """

  @behaviour Instructor.Adapter
  alias Instructor.SSEStreamParser
  alias Instructor.Adapters
  alias Instructor.JSONSchema

  @supported_modes [:json_schema]

  @doc """
  Run a completion against Google's Gemini API
  Accepts OpenAI API arguments and converts to Gemini Args to perform the completion.
  Defaults to JSON mode within the Gemini API
  """
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
      raise "Unsupported Gemini mode #{mode}. Supported modes: #{inspect(@supported_modes)}"
    end

    # Format the messages into the correct format for Geminic
    {messages, params} = Map.pop!(params, :messages)

    {system_instruction, contents} =
      messages
      |> Enum.reduce({%{role: "system", parts: []}, []}, fn
        %{role: "assistant", content: content}, {system_instructions, history} ->
          {system_instructions, [%{role: "model", parts: [%{text: content}]} | history]}

        %{role: "user", content: content}, {system_instructions, history}
        when is_binary(content) ->
          {system_instructions, [%{role: "user", parts: [%{text: content}]} | history]}

        %{role: "user", content: content}, {system_instructions, history} ->
          parts =
            Enum.map(content, fn
              %{type: "text", text: text} ->
                %{text: text}

              %{type: "image_url", image_url: %{url: url, mime_type: mime_type}} ->
                %{file_data: %{mime_type: mime_type, file_uri: url}}

              %{type: "video_url", video_url: %{url: url, mime_type: mime_type}} ->
                %{file_data: %{mime_type: mime_type, file_uri: url}}
            end)

          {system_instructions, [%{role: "user", parts: parts} | history]}

        %{role: "system", content: content}, {system_instructions, history} ->
          part = %{text: content}
          {Map.update!(system_instructions, :parts, fn parts -> [part | parts] end), history}
      end)

    system_instruction = Map.update!(system_instruction, :parts, &Enum.reverse/1)
    contents = Enum.reverse(contents)

    # Split out the model config params from the rest of the params
    {model_config_params, params} =
      Map.split(params, [:top_k, :top_p, :max_tokens, :temperature, :n, :stop])

    generation_config =
      model_config_params
      |> Enum.into(%{}, fn
        {:stop, stops} ->
          {"stopSequences", stops}

        {:n, n} ->
          {"candidateCount", n}

        {:max_tokens, max_tokens} ->
          {"maxOutputTokens", max_tokens}

        {other_key, value} ->
          {Atom.to_string(other_key) |> snake_to_camel(), value}
      end)

    params =
      if system_instruction.parts != [],
        do: Map.put(params, :systemInstruction, system_instruction),
        else: params

    params = Map.put(params, :contents, contents)

    params =
      case params do
        %{response_format: %{json_schema: %{schema: schema}}} ->
          generation_config =
            generation_config
            |> Map.put("response_mime_type", "application/json")
            |> Map.put("response_schema", normalize_json_schema(schema))

          params
          |> Map.put(:generationConfig, generation_config)
          |> Map.delete(:response_format)
          |> Map.put(:safetySettings, [
            %{category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE"},
            %{category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE"},
            %{category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE"},
            %{category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE"},
            %{category: "HARM_CATEGORY_CIVIC_INTEGRITY", threshold: "BLOCK_NONE"}
          ])

        %{tools: tools} ->
          tools = [
            %{
              function_declarations:
                Enum.map(tools, fn %{function: tool} ->
                  %{
                    name: tool["name"],
                    description: tool["description"],
                    parameters: normalize_json_schema(tool["parameters"])
                  }
                end)
            }
          ]

          params
          |> Map.put(:generationConfig, generation_config)
          |> Map.put(:tools, tools)
          |> Map.delete(:tool_choice)

        _ ->
          params
      end

    if stream do
      do_streaming_chat_completion(mode, params, config)
    else
      do_chat_completion(mode, params, config)
    end
  end

  defp do_streaming_chat_completion(mode, params, config) do
    pid = self()
    options = http_options(config)
    {model, params} = Map.pop!(params, :model)
    {_, params} = Map.pop!(params, :stream)

    Stream.resource(
      fn ->
        Task.async(fn ->
          options =
            Keyword.merge(options,
              url: url(config) <> "?alt=sse",
              path_params: [model: model, api_version: api_version(config)],
              headers: %{"x-goog-api-key" => api_key(config)},
              json: params,
              rpc_function: :streamGenerateContent,
              into: fn {:data, data}, {req, resp} ->
                send(pid, data)
                {:cont, {req, resp}}
              end
            )

          Req.merge(gemini_req(), options)
          |> Req.post!()

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

    response =
      Req.merge(gemini_req(), http_options(config))
      |> Req.post(
        url: url(config),
        path_params: [model: model, api_version: api_version(config)],
        headers: %{"x-goog-api-key" => api_key(config)},
        json: params,
        rpc_function: :generateContent
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

  defp parse_response_for_mode(:tools, %{
         "candidates" => [
           %{"content" => %{"parts" => [%{"functionCall" => %{"args" => args}}]}}
         ]
       }) do
    {:ok, args}
  end

  defp parse_response_for_mode(:json_schema, %{
         "candidates" => [
           %{"content" => %{"parts" => [%{"text" => text}]}}
         ]
       }) do
    Jason.decode(text)
  end

  defp parse_stream_chunk_for_mode(
         :tools,
         %{
           "candidates" => [
             %{
               "content" => %{
                 "parts" => [%{"functionCall" => %{"args" => args}}]
               }
             }
           ]
         }
       ) do
    args
  end

  defp parse_stream_chunk_for_mode(:json_schema, %{
         "candidates" => [
           %{
             "content" => %{
               "parts" => [%{"text" => chunk}]
             }
           }
         ]
       }) do
    chunk
  end

  defp normalize_json_schema(schema) do
    JSONSchema.traverse_and_update(
      schema,
      fn
        {%{"type" => _} = x, path}
        when is_map_key(x, "format") or is_map_key(x, "pattern") or
               is_map_key(x, "title") or is_map_key(x, "additionalProperties") ->
          x
          |> Map.drop(["format", "pattern", "title", "additionalProperties"])
          |> case do
            %{"type" => "object", "properties" => properties} when map_size(properties) == 0 ->
              raise """
              Invalid JSON Schema: object with no properties at path: #{inspect(path)}

              Gemini does not support empty objects. This is likely because have have a naked :map type
              without any fields at #{inspect(path)}. Try switching to an embedded schema instead.
              """

            x ->
              x
          end

        {x, _path} ->
          x
      end,
      include_path: true
    )
    |> inline_defs()
  end

  defp inline_defs(schema) do
    # First extract the definitions map for reference
    {defs, schema} = Map.pop(schema, "$defs", %{})

    # Traverse and replace all $refs with their definitions
    traverse_and_inline(schema, defs)
  end

  defp traverse_and_inline(schema, defs) when is_map(schema) do
    cond do
      # If we find a $ref, replace it with the inlined definition
      Map.has_key?(schema, "$ref") ->
        ref = schema["$ref"]
        def_key = String.replace_prefix(ref, "#/$defs/", "")
        definition = Map.get(defs, def_key, %{})
        # Recursively inline any nested refs in the definition
        traverse_and_inline(definition, defs)

      # Otherwise traverse all values in the map
      true ->
        schema
        |> Enum.map(fn {k, v} -> {k, traverse_and_inline(v, defs)} end)
        |> Enum.into(%{})
    end
  end

  # Handle arrays by traversing each element
  defp traverse_and_inline(schema, defs) when is_list(schema) do
    Enum.map(schema, &traverse_and_inline(&1, defs))
  end

  # Base case - return non-map/list values as is
  defp traverse_and_inline(schema, _defs), do: schema

  defp snake_to_camel(snake_case_string) do
    snake_case_string
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn {word, index} ->
      if index == 0 do
        String.downcase(word)
      else
        String.capitalize(word)
      end
    end)
    |> Enum.join("")
  end

  defp gemini_req,
    do:
      Req.new()
      |> Req.Request.register_options([:rpc_function])
      |> Req.Request.append_request_steps(
        append_rpc_function: fn request ->
          rpc_function = request.options[:rpc_function]

          if rpc_function do
            update_in(request.url.path, fn
              nil -> nil
              path -> path <> inspect(rpc_function)
            end)
          else
            request
          end
        end
      )

  @impl true
  defdelegate reask_messages(raw_response, params, config), to: Adapters.OpenAI

  defp url(config), do: api_url(config) <> ":api_version/models/:model"
  defp api_url(config), do: Keyword.fetch!(config, :api_url)
  defp api_key(config), do: Keyword.fetch!(config, :api_key)
  defp api_version(config), do: Keyword.fetch!(config, :api_version)
  defp http_options(config), do: Keyword.fetch!(config, :http_options)
  defp config(nil), do: config(Application.get_env(:instructor, :gemini, []))

  defp config(base_config) do
    default_config = [
      api_version: :v1beta,
      api_url: "https://generativelanguage.googleapis.com/",
      api_key: System.get_env("GOOGLE_API_KEY"),
      http_options: [receive_timeout: 60_000]
    ]

    Keyword.merge(default_config, base_config)
  end
end
