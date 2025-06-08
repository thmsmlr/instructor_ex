# Web Automation with instructor_ex

This example demonstrates how to combine instructor_ex with web automation to extract structured data from web content.

## Overview

The integration showcases the following features:

1. **Web Automation**: Using web automation tools to navigate websites and extract information
2. **Structured Data Extraction**: Leveraging instructor_ex to extract typed data from web content
3. **Multiple Automation Options**: Support for both API-based proxy services and the proxy-lite-3b model
4. **Prompt Engineering**: Techniques to ensure complete and accurate information extraction
5. **Error Handling**: Reliable processing of web automation results

## How It Works

The example follows this pattern:

1. Define schemas using Ecto and Instructor that represent the structured data you want to extract
2. Perform web automation to navigate websites and search for information
3. Extract the content and results from the automation
4. Use instructor_ex to process the content and extract structured data
5. Present the results to the user

## Automation Options

This example provides two different approaches to web automation:

### 1. proxy-lite Service (Original)

A FastAPI-based web automation service that uses Playwright for browser automation. This runs as a separate service that exposes a REST API.

### 2. proxy-lite-3b Model (Recommended)

An AI model designed specifically for web automation tasks. This is a 3B parameter Vision-Language Model from Convergence AI that:

- Processes web page screenshots and HTML content
- Decides what actions to take based on the content
- Executes web tasks autonomously
- Works directly from Python without requiring a separate service

## Running the Example

### Prerequisites

- Elixir 1.14+
- A running llama.cpp server with a compatible model
- Python 3.11+ (for proxy-lite-3b model)
- Either:
  - A web automation service (for the proxy service approach), or
  - The proxy-lite-3b model dependencies (for the model approach)

### Setup for proxy-lite-3b (Recommended)

1. Install the proxy-lite dependencies:
   ```bash
   # Clone the repo
   git clone https://github.com/convergence-ai/proxy-lite.git
   cd proxy-lite
   
   # Set up the environment
   pip install uv
   uv venv --python 3.11
   uv sync
   uv pip install -e .
   playwright install
   ```

2. Start the llama.cpp server:
   ```bash
   llama-server --port 8090 -ngl 1 -m /path/to/your/model.gguf
   ```

3. Ensure the `proxy_lite_example.py` script is in your working directory

4. Make the example executable:
   ```bash
   chmod +x web_automation_example.exs
   ```

5. Run the example:
   ```bash
   ./web_automation_example.exs "your search query" --client proxy_lite_3b --homepage "https://en.wikipedia.org"
   ```

### Setup for proxy-lite Service (Alternative)

1. Start the llama.cpp server:
   ```bash
   llama-server --port 8090 -ngl 1 -m /path/to/your/model.gguf
   ```

2. Start the proxy-lite service:
   ```bash
   python proxy_service.py
   ```

3. Make the example executable:
   ```bash
   chmod +x web_automation_example.exs
   ```

4. Run the example:
   ```bash
   ./web_automation_example.exs "your search query" --client proxy_lite
   ```

## Key Components

### WebSearchResult Schema

A schema for structured search results.

### WebAutomationSummary Schema

A schema for summarizing web automation sessions.

### ProxyClient & ProxyLite3bClient

Client modules for interacting with the web automation options:
- `ProxyClient`: For the original proxy service
- `ProxyLite3bClient`: For the proxy-lite-3b model

### WebAutomation Module

The main module that ties everything together, handling the automation and structured extraction.

## Best Practices

1. **Use Wikipedia as a Starting Point**: Using Wikipedia as the homepage (`--homepage "https://en.wikipedia.org"`) usually avoids CAPTCHA issues and provides reliable results
2. **Choose the Right Client**: The proxy-lite-3b model is generally more reliable but requires Python setup
3. **Timeout Management**: Set appropriate timeouts for web requests
4. **Error Handling**: Be prepared to handle CAPTCHAs and other errors
5. **Task Specificity**: Be clear and specific about what you want the automation to do
6. **Content Slicing**: Limit HTML content size to avoid token limits 

## Customization

You can adapt this example to various use cases:

1. **Different Data Types**: Create new schemas for specific data types (weather, products, news)
2. **Alternative Web Services**: Implement clients for other automation services
3. **Advanced Validation**: Add custom validation logic to ensure data quality
4. **Custom Prompt Engineering**: Refine prompts for specific extraction tasks

## Troubleshooting

- **CAPTCHA Issues**: Some sites like Google may present CAPTCHAs. Using Wikipedia as a starting point can help avoid this.
- **Model Loading Errors**: Ensure you have the required GPU memory (at least 8GB) for running the llama.cpp server.
- **Browser Automation Issues**: Make sure you've installed Playwright and its browser dependencies.
- **Parsing Errors**: If you're not getting the expected results, check the regular expressions used for parsing outputs. 