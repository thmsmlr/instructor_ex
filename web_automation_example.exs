#!/usr/bin/env elixir

# Example of using instructor_ex with web automation
# This example demonstrates how to extract structured data from web content
# using instructor_ex and a web automation service (proxy-lite or proxy-lite-3b)

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

# Simple client for the legacy proxy-lite service
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

# Client for the proxy-lite-3b model (using Python script)
defmodule ProxyLite3bClient do
  @moduledoc """
  Client for executing web automation using the proxy-lite-3b model.
  This client calls the proxy_lite_example.py script directly.
  """

  def run_task(query, opts \\ []) do
    # Default options
    homepage = Keyword.get(opts, :homepage, "https://en.wikipedia.org") # Wikipedia works better by default
    headless = Keyword.get(opts, :headless, true)
    max_steps = Keyword.get(opts, :max_steps, 20)
    
    IO.puts("🤖 Running web automation using proxy-lite-3b for: #{query}")
    
    # Create the command arguments
    args = [
      "proxy_lite_example.py",
      query,
      "--headless",
      "--homepage", 
      homepage,
      "--max-steps", 
      to_string(max_steps)
    ]
    
    # Run the Python script and capture output
    try do
      {output, exit_code} = System.cmd("python", args, stderr_to_stdout: true)
      
      # Check exit code
      if exit_code != 0 do
        {:error, "Python script exited with code #{exit_code}: #{output}"}
      else
        # Parse the output to extract results
        results = parse_output(output, query)
        
        if results[:success] do
          {:ok, %{
            "status" => "success",
            "results" => %{
              "query" => query,
              "steps" => results[:steps] || [],
              "steps_taken" => results[:steps_taken] || 0,
              "output" => results[:answer]
            },
            "html_content" => "<html><body>Results extracted from webpage</body></html>",
            "screenshots" => [results[:screenshot_path]]
          }}
        else
          {:error, results[:answer] || "Failed to complete the task"}
        end
      end
    rescue
      e -> 
        IO.puts("Error running web automation: #{inspect(e)}")
        {:error, "Failed to execute web automation: #{inspect(e)}"}
    end
  end
  
  # Helper function to parse Python script output
  defp parse_output(output, query) do
    # Extract information from the command output
    steps_taken = 
      case Regex.run(~r/Automation completed with (\d+) steps/, output) do
        [_, steps] -> String.to_integer(steps)
        _ -> 0
      end
      
    answer =
      case Regex.run(~r/Answer: (.+?)(?=\n\n|\Z)/s, output) do
        [_, answer] -> String.trim(answer)
        _ -> 
          # Check for errors
          case Regex.run(~r/Error during web automation: (.+)$/, output, multiline: true) do
            [_, error] -> "Error: #{String.trim(error)}"
            _ -> "No answer found in output"
          end
      end
      
    screenshot_path =
      case Regex.run(~r/See final screenshot at: (.+)$/, output, multiline: true) do
        [_, path] -> String.trim(path)
        _ -> nil
      end
      
    gif_path =
      case Regex.run(~r/See animation at: (.+)$/, output, multiline: true) do
        [_, path] -> String.trim(path)
        _ -> nil
      end
    
    # Check if the output contains CAPTCHA references
    captcha_detected = String.contains?(output, "CAPTCHA") || String.contains?(output, "I'm not a robot")
    
    # Determine success based on answer and CAPTCHA detection
    success = answer != "No answer found in output" && !String.starts_with?(answer, "Error:")
    
    # Adjust answer if CAPTCHA was detected but not already mentioned
    answer = if captcha_detected && !String.contains?(answer, "CAPTCHA") && !String.contains?(answer, "robot") do
      if answer == "No answer found in output" do
        "A CAPTCHA challenge was encountered, which prevented completing the task."
      else
        answer <> " Note: A CAPTCHA challenge was encountered during the task."
      end
    else
      answer
    end
    
    %{
      query: query,
      answer: answer,
      steps_taken: steps_taken,
      success: success,
      screenshot_path: screenshot_path,
      gif_path: gif_path
    }
  end
end

# Integration module that combines web automation and instructor_ex
defmodule WebAutomation do
  def search_and_extract(query, opts \\ []) do
    # Default options
    client = Keyword.get(opts, :client, :proxy_lite_3b)
    homepage = Keyword.get(opts, :homepage, "https://en.wikipedia.org")
    headless = Keyword.get(opts, :headless, true)
    max_steps = Keyword.get(opts, :max_steps, 20)
    
    # Configure instructor to use an LLM adapter (llama.cpp in this example)
    config = [
      adapter: Instructor.Adapters.Llamacpp,
      api_url: "http://localhost:8090"
    ]
    
    # Step 1: Perform the web automation task with selected client
    web_task_result = case client do
      :proxy_lite -> 
        ProxyClient.run_task(query, homepage: homepage, headless: headless)
      
      :proxy_lite_3b -> 
        ProxyLite3bClient.run_task(query, 
          homepage: homepage, 
          headless: headless, 
          max_steps: max_steps
        )
      
      _ -> 
        {:error, "Invalid client selected: #{client}"}
    end
    
    # Step 2: Process the web automation results
    with {:ok, result} <- web_task_result,
         true <- result["status"] == "success" do
      
      # Extract relevant data from the result
      html_content = result["html_content"] || ""
      steps = result["results"]["steps"] || []
      steps_count = result["results"]["steps_taken"] || length(steps)
      
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
      
      # Step 3: Use instructor_ex to extract structured data
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
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Failed to get successful response from web automation service"}
    end
  end
end

defmodule WebAutomationExample do
  def parse_args([]), do: {nil, []}
  def parse_args([query | rest]), do: {query, parse_options(rest)}

  defp parse_options([]), do: []
  defp parse_options(["--client", "proxy_lite" | rest]), do: [client: :proxy_lite] ++ parse_options(rest)
  defp parse_options(["--client", "proxy_lite_3b" | rest]), do: [client: :proxy_lite_3b] ++ parse_options(rest)
  defp parse_options(["--homepage", url | rest]), do: [homepage: url] ++ parse_options(rest)
  defp parse_options([_ | rest]), do: parse_options(rest)

  def main(args) do
    case args do
      ["--help"] ->
        IO.puts("Usage: ./web_automation_example.exs [search query] [--client proxy_lite|proxy_lite_3b] [--homepage URL]")
        IO.puts("\nOptions:")
        IO.puts("  --client proxy_lite    Use the original proxy-lite service (default: proxy_lite_3b)")
        IO.puts("  --client proxy_lite_3b Use the proxy-lite-3b model (recommended)")
        IO.puts("  --homepage URL         Set the starting URL (default: https://en.wikipedia.org)")
        IO.puts("\nExample: ./web_automation_example.exs \"current weather in San Francisco\" --client proxy_lite_3b --homepage https://en.wikipedia.org")
    
      args ->
        # Parse arguments
        {query, options} = parse_args(args)
        
        if query == nil do
          IO.puts("Using default query: \"current weather in San Francisco\"")
          query = "current weather in San Francisco"
        else
          IO.puts("🚀 Performing web search for: #{query}")
        end
        
        # Show selected options
        client = Keyword.get(options, :client, :proxy_lite_3b)
        homepage = Keyword.get(options, :homepage, "https://en.wikipedia.org")
        IO.puts("Using client: #{client}, Homepage: #{homepage}")
        
        case WebAutomation.search_and_extract(query, options) do
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
  end
end

# Run the script
WebAutomationExample.main(System.argv()) 