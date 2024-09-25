# Used by "mix format"
[
  import_deps: [:ecto, :phoenix, :phoenix_live_view],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "pages/cookbook/**/*.{ex,exs}"]
]
