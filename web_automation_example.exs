#!/usr/bin/env elixir

# Example of using instructor_ex with web automation
# This example demonstrates how to extract structured data from web content
# using instructor_ex and a web automation service (proxy-lite)

# First, ensure dependencies are available
Mix.install([
  {:instructor, github: "thmsmlr/instructor_ex"},
  {:ecto, "~> 3.12"},
  {:jason, "~> 1.4"},
  {:httpoison, "~> 2.0"}
])

# Define schemas for structured data extraction
defmodule WebSearchResult do
  @moduledoc """
  Schema for search results extracted from web automation.
  """
  use Ecto.Schema
  use Instructor

  @llm_doc """
  Schema for web search results extracted from web automation.

  ## Field Descriptions:
  - query: The original search query
  - results: A list of search result items with titles and descriptions
  - summary: A concise summary of the search results
  - top_result: The most relevant result from the search
  """
  @primary_key false
  embedded_schema do
    field(:query, :string)
    field(:results, {:array, :map})
    field(:summary, :string)
    field(:top_result, :string)
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:query, :summary])
  end
end

defmodule WebAutomationSummary do
  @moduledoc """
  Schema for summarizing the entire web automation session.
  """
  use Ecto.Schema
  use Instructor

  @llm_doc """
  Schema for summarizing the entire web automation session results.

  ## Field Descriptions:
  - task_completed: Whether the task was completed successfully
  - steps_taken: Number of steps taken during automation
  - summary: A concise summary of what was accomplished
  - answer: The direct answer to the original query, if applicable
  """
  @primary_key false
  embedded_schema do
    field(:task_completed, :boolean)
    field(:steps_taken, :integer)
    field(:summary, :string)
    field(:answer, :string)
  end

  @impl true
  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:task_completed, :summary])
  end
end

# Simple client for the proxy-lite service
defmodule ProxyClient do
  @proxy_service_url "http://localhost:8001"

  def run_task(query, opts \\ []) do
    # Default options
    homepage = Keyword.get(opts, :homepage, "https://www.google.com")
    headless = Keyword.get(opts, :headless, false)
    include_html = Keyword.get(opts, :include_html, true)
    
    # Prepare the request body
    body = %{
      query: query,
      homepage: homepage,
      headless: headless,
      include_html: include_html
    }
    
    # Make the HTTP request to the proxy service
    case HTTPoison.post(
      "#{@proxy_service_url}/run",
      Jason.encode!(body),
      [{"Content-Type", "application/json"}],
      recv_timeout: 300_000  # 5-minute timeout
    ) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}
        
      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, "HTTP Error #{code}: #{body}"}
        
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "HTTP Request Failed: #{inspect(reason)}"}
    end
  end
end

# Integration module that combines proxy-lite and instructor_ex
defmodule WebAutomation do
  def search_and_extract(query) do
    # Configure instructor to use an LLM adapter (llama.cpp in this example)
    config = [
      adapter: Instructor.Adapters.Llamacpp,
      api_url: "http://localhost:8090"
    ]
    
    # Step 1: Perform the web automation task
    with {:ok, result} <- ProxyClient.run_task(query),
         true <- result["status"] == "success" do
      
      # Extract relevant data from the result
      html_content = result["html_content"] || ""
      steps = result["results"]["steps"] || []
      steps_count = length(steps)
      
      # Extract the final answer if available
      final_answer = cond do
        # Try to get from the output field
        is_map(result["results"]) && is_binary(result["results"]["output"]) ->
          result["results"]["output"]
          
        # Try to get from the last step's output
        is_list(steps) && length(steps) > 0 ->
          last_step = List.last(steps)
          if is_map(last_step) && is_binary(last_step["output"]), do: last_step["output"], else: nil
          
        # No final answer found
        true -> nil
      end
      
      # Step 2: Use instructor_ex to extract structured data
      Instructor.chat_completion(
        [
          response_model: WebAutomationSummary,
          mode: :json_schema,
          messages: [
            %{
              role: "user",
              content: """
              I performed a web search for: "#{query}"
              
              The task took #{steps_count} steps to complete.
              
              The final page content included:
              
              #{html_content |> String.slice(0, 5000)}
              
              #{if final_answer, do: "The final result was: #{final_answer}", else: ""}
              
              Please provide a detailed summary of what was accomplished, including the complete answer.
              """
            }
          ]
        ],
        config
      )
    else
      {:error, _reason} = error -> error
      _ -> {:error, "Failed to get successful response from web automation service"}
    end
  end
end

# Main example code
case System.argv() do
  ["--help"] ->
    IO.puts("Usage: ./web_automation_example.exs [search query]")
    IO.puts("Example: ./web_automation_example.exs \"current weather in San Francisco\"")
  
  [query] ->
    IO.puts("🚀 Performing web search for: #{query}")
    
    case WebAutomation.search_and_extract(query) do
      {:ok, result} ->
        IO.puts("\n✅ Task completed!")
        IO.puts("\nSummary: #{result.summary}")
        
        if result.answer && result.answer != "" do
          IO.puts("\nAnswer: #{result.answer}")
        end
        
        IO.puts("\nSteps taken: #{result.steps_taken || 0}")
      
      {:error, reason} ->
        IO.puts("\n❌ ERROR: #{reason}")
    end
  
  _ ->
    IO.puts("Using default query: \"current weather in San Francisco\"")
    
    case WebAutomation.search_and_extract("current weather in San Francisco") do
      {:ok, result} ->
        IO.puts("\n✅ Task completed!")
        IO.puts("\nSummary: #{result.summary}")
        
        if result.answer && result.answer != "" do
          IO.puts("\nAnswer: #{result.answer}")
        end
        
        IO.puts("\nSteps taken: #{result.steps_taken || 0}")
      
      {:error, reason} ->
        IO.puts("\n❌ ERROR: #{reason}")
    end
end 