# Azure OpenAI

Configure your project like so to [issue requests against Azure OpenAI](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#chat-completions):

```elixir
config: [
  instructor: [
    adapter: Instructor.Adapters.OpenAI,
    openai: [
      auth_mode: :api_key,
      api_key: System.fetch_env!("AZURE_API_KEY"),
      api_url: "[AZURE_OPENAI_RESOURCE_ENDPOINT]",
      api_path: "/openai/deployments/[AZURE_OPENAI_DEPLOYMENT_NAME]/chat/completions?api-version=2024-02-01"
    ]
  ]
]
```
