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

The code below contains a simple GenServer that continuously refreshes the access token for a service principal. Instead of setting the configuration to a fixed access token (that would expire after an hour), the `api_key` is set to a /0-arity function that returns the most recently fetched access token.

```elixir
defmodule AzureServicePrincipalTokenRefresher do
  use GenServer

  @derive {Inspect,
           only: [:tenant_id, :client_id, :scope, :error], except: [:client_secret, :access_token]}
  @enforce_keys [:tenant_id, :client_id, :client_secret, :scope]
  defstruct [:tenant_id, :client_id, :client_secret, :scope, :access_token, :error]

  def get_token_func!(tenant_id, client_id, client_secret, scope) do
    {:ok, pid} = __MODULE__.start_link(tenant_id, client_id, client_secret, scope)

    fn ->
      case __MODULE__.get_access_token(pid) do
        {:ok, access_token} -> access_token
        {:error, error} -> raise "Could not fetch Microsoft Entra ID token: #{inspect(error)}"
      end
    end
  end

  def start_link(tenant_id, client_id, client_secret, scope) do
    GenServer.start_link(__MODULE__, %__MODULE__{
      tenant_id: tenant_id,
      client_id: client_id,
      client_secret: client_secret,
      scope: scope
    })
  end

  def get_access_token(pid) do
    GenServer.call(pid, :get_access_token)
  end

  @impl GenServer
  def init(%__MODULE__{} = state) do
    {:ok, state, {:continue, :fetch_token}}
  end

  @impl GenServer
  def handle_call(:get_access_token, _from, %__MODULE__{} = state) do
    case state do
      %__MODULE__{access_token: access_token, error: nil} ->
        {:reply, {:ok, access_token}, state}

      %__MODULE__{access_token: nil, error: error} ->
        {:reply, {:error, error}, state}
    end
  end

  @impl GenServer
  def handle_continue(:fetch_token, %__MODULE__{} = state) do
    {:noreply, fetch_token(state)}
  end

  @impl GenServer
  def handle_info(:refresh_token, %__MODULE__{} = state) do
    {:noreply, fetch_token(state)}
  end

  defp fetch_token(%__MODULE__{} = state) do
    %__MODULE__{
      tenant_id: tenant_id,
      client_id: client_id,
      client_secret: client_secret,
      scope: scope
    } = state

    case Req.post(
           url: "https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token",
           form: [
             grant_type: "client_credentials",
             scope: scope,
             client_id: client_id,
             client_secret: client_secret
           ]
         ) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "access_token" => access_token,
           "expires_in" => expires_in
         }
       }} ->
        fetch_new_token_timeout = to_timeout(%Duration{second: expires_in - 60})
        Process.send_after(self(), :refresh_token, fetch_new_token_timeout)
        %__MODULE__{state | access_token: access_token, error: nil}

      {:ok, response} ->
        %__MODULE__{state | access_token: nil, error: response}

      {:error, error} ->
        %__MODULE__{state | access_token: nil, error: error}
    end
  end
end
```

Then use the helper class to configure the dynamic credential:

```elixir
config: [
  instructor: [
    adapter: Instructor.Adapters.OpenAI,
    openai: [
      auth_mode: :bearer, 
      api_key: AzureServicePrincipalTokenRefresher.get_token_func!(
          System.get_env("LB_AZURE_ENTRA_TENANT_ID"), # e.g. "contoso.onmicrosoft.com"
          System.get_env("LB_AZURE_OPENAI_CLIENT_ID"), # e.g. "deadbeef-0000-4f13-afa9-c8a1e4087f97"
          System.get_env("LB_AZURE_OPENAI_CLIENT_SECRET"), # e.g. "mEf8Q~.e2e8URInwinsermNe8wDewsedRitsen.."}, 
          "https://cognitiveservices.azure.com/.default"
      ),  
      api_url: azure_openai_endpoint,
      api_path: azure_openai_api_path
    ]
  ]
]
```