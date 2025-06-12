import Config

config :logger, :default_formatter,
  format: "[$level] $message $metadata\n",
  metadata: [:errors, :file]

config :instructor,
    adapter: Instructor.Adapters.OpenAI,
    openai: [api_key: System.fetch_env!("OPENAI_API_KEY")]
