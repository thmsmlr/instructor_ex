import Config

config :logger, :default_formatter,
  format: "[$level] $message $metadata\n",
  metadata: [:errors, :file]
