# Azure OpenAI

Configure your project like so to [issue requests against Azure OpenAI](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#chat-completions), according to the [docs](https://learn.microsoft.com/en-us/azure/ai-services/openai/reference#authentication).

```elixir
azure_openai_endpoint = "https://contoso.openai.azure.com"
azure_openai_deployment_name = "contosodeployment123"
azure_openai_api_path = "/openai/deployments/#{azure_openai_deployment_name}/chat/completions?api-version=2024-02-01"
```

The Azure OpenAI service supports two authentication methods, API key and Entra ID. API key-based authN is conveyed in the `api-key` HTTP header, while Entra ID-issued access tokens go into the `Authorization: Bearer` header:

## API Key Authentication

```elixir
config: [
  instructor: [
    adapter: Instructor.Adapters.OpenAI,
    openai: [
      auth_mode: :api_key_header, 
      api_key: System.get_env("LB_AZURE_OPENAI_API_KEY"), # e.g. "c3829729deadbeef382938acdfee2987"
      api_url: azure_openai_endpoint,
      api_path:azure_openai_api_path
    ]
  ]
]
```

## Microsoft Entra ID authentication

```elixir
entra_tenant_id = System.get_env("LB_AZURE_ENTRA_TENANT_ID") # e.g. "contoso.onmicrosoft.com"
entra_client_id = System.get_env("LB_AZURE_OPENAI_CLIENT_ID") # e.g. "deadbeef-0000-4f13-afa9-c8a1e4087f97"
entra_client_secret = System.get_env("LB_AZURE_OPENAI_CLIENT_SECRET") # e.g. "mEf8Q~.e2e8URInwinsermNe8wDewsedRitsen.."}
   
%Req.Response{status: 200, body: %{"access_token" => azure_openai_access_token }} = Req.post!(
    url: "https://login.microsoftonline.com/#{entra_tenant_id}/oauth2/v2.0/token",
    form: [
      grant_type: "client_credentials",
      scope:  "https://cognitiveservices.azure.com/.default",
      client_id: entra_client_id, client_secret: entra_client_secret
    ]
  )
```

Then use the `azure_openai_access_token` to call

```elixir
config: [
  instructor: [
    adapter: Instructor.Adapters.OpenAI,
    openai: [
      auth_mode: :bearer, 
      api_key: azure_openai_access_token,  
      api_url: azure_openai_endpoint,
      api_path:azure_openai_api_path
    ]
  ]
]
```