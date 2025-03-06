# Web Automation with instructor_ex

This example demonstrates how to combine instructor_ex with web automation to extract structured data from web content.

## Overview

The integration showcases the following features:

1. **Web Automation**: Using a simple HTTP client to interact with a web automation service
2. **Structured Data Extraction**: Leveraging instructor_ex to extract typed data from web content
3. **Prompt Engineering**: Techniques to ensure complete and accurate information extraction
4. **Error Handling**: Reliable processing of web automation results

## How It Works

The example follows this pattern:

1. Define schemas using Ecto and Instructor that represent the structured data you want to extract
2. Perform web automation to navigate websites and search for information
3. Extract the HTML content and other results from the automation
4. Use instructor_ex to process the content and extract structured data
5. Present the results to the user

## Running the Example

### Prerequisites

- Elixir 1.14+
- A running llama.cpp server with a compatible model
- A web automation service (the example uses a simple proxy service)

### Setup

1. Start the llama.cpp server:
   ```
   llama-server --port 8090 -ngl 1 -m /path/to/your/model.gguf
   ```

2. Start a web automation service (a simple proxy service is used in the example)

3. Make the example executable:
   ```
   chmod +x web_automation_example.exs
   ```

4. Run the example:
   ```
   ./web_automation_example.exs "your search query"
   ```

## Key Components

### WebSearchResult Schema

A schema for structured search results.

### WebAutomationSummary Schema

A schema for summarizing web automation sessions.

### Prompt Engineering Techniques

The example demonstrates several prompt engineering techniques:

1. **Explicit Instructions**: Providing clear directives to the LLM about what to extract
2. **Context Preservation**: Including relevant context from the web content
3. **Answer Extraction**: Finding and providing the complete answer from automation results
4. **Field Mapping**: Structuring prompts to match schema fields

## Customization

You can adapt this example to various use cases:

1. **Different Data Types**: Create new schemas for specific data types (weather, products, news)
2. **Alternative Web Services**: Replace the ProxyClient with clients for other services (Selenium, Puppeteer)
3. **Advanced Validation**: Add custom validation logic to ensure data quality

## Best Practices

1. **Timeout Management**: Set appropriate timeouts for web requests
2. **Error Handling**: Implement comprehensive error handling
3. **Data Validation**: Use Ecto validations to ensure data quality
4. **Prompt Clarity**: Keep prompts clear and focused on the data you need
5. **Content Slicing**: Limit HTML content size to avoid token limits 