Mix.install([
  {:phoenix_playground, github: "gmile/phoenix_playground", branch: "handle-async-callback"},
  {:instructor, path: Path.expand("~/code/instructor_ex")}
])

defmodule DemoLive do
  use Phoenix.LiveView
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.AsyncResult

  @instructor_config [
    adapter: Instructor.Adapters.OpenAI,
    api_key: System.get_env("OPENAI_API_KEY")
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       selected_model: "gpt-4o-mini",
       models: ["gpt-4o", "gpt-4o-mini"],
       prompt: """
       Emily is organizing a bake sale. She plans to bake cookies and brownies. She wants to make 5 batches of cookies and 3 batches of brownies.

       Each batch of cookies requires 2 cups of flour, and each batch of brownies requires 3 cups of flour.
       Emily has a total of 32 cups of flour.
       After baking the cookies and brownies, Emily will sell each batch of cookies for $15 and each batch of brownies for $20.

       How many cups of flour will she have left over and how much money will she make from selling all the cookies and brownies she bakes?
       """,
       output_schema: [
         {"flour_left_over", :integer},
         {"money_made", :decimal}
       ],
       cot_messages: AsyncResult.ok([]),
       messages: AsyncResult.ok([])
     )}
  end

  def handle_event("select_model", %{"model" => selected}, socket) do
    {:noreply, socket |> assign(:selected_model, selected)}
  end

  def handle_event("send_message", %{"prompt" => prompt}, socket) do
    pid = self()

    selected_model = socket.assigns.selected_model
    response_model =
      socket.assigns.output_schema
      |> Enum.map(fn {key, type} -> {String.to_atom(key), type} end)
      |> Enum.into(%{})

    socket =
      socket
      |> assign(:cot_messages, AsyncResult.ok([]))
      |> assign(:messages, AsyncResult.ok([]))
      |> assign_async(:cot_messages, fn ->
        messages =
          Instructor.Extras.ChainOfThought.chat_completion(
            [
              model: selected_model,
              response_model: response_model,
              messages: [
                %{role: "user", content: prompt}
              ]
            ],
            @instructor_config
          )
          |> Stream.each(fn
            x ->
              send(pid, {:cot_messages, x})
              x
          end)
          |> Enum.to_list()

        {:ok, %{cot_messages: messages}}
      end)
      |> assign_async(:messages, fn ->
        {:ok, final_answer} =
          Instructor.chat_completion(
            [
              model: selected_model,
              response_model: response_model,
              messages: [
                %{role: "user", content: prompt}
              ]
            ],
            @instructor_config
          )

        {:ok, %{messages: [final_answer]}}
      end)

    {:noreply, socket}
  end

  def handle_info({panel, message}, socket) when panel in [:cot_messages, :messages] do
    {:noreply, socket |> assign(panel, AsyncResult.ok(socket.assigns[panel].result ++ [message]))}
  end

  def handle_async(panel, {:ok, message}, socket) when panel in [:cot_messages, :messages] do
    {:noreply, socket |> assign(panel, AsyncResult.ok(socket.assigns[panel].result ++ [message]))}
  end

  def handle_async(panel, {:error, error}, socket) when panel in [:cot_messages, :messages] do
    {:noreply, socket |> assign(panel, AsyncResult.error(error))}
  end

  def handle_event("add_schema_field", _params, socket) do
    {:noreply, socket |> assign(:output_schema, socket.assigns.output_schema ++ [{"", :string}])}
  end

  def handle_event("remove_schema_field", %{"idx" => idx}, socket) do
    output_schema = List.delete_at(socket.assigns.output_schema, String.to_integer(idx))
    {:noreply, socket |> assign(:output_schema, output_schema)}
  end

  def handle_event(
        "update_settings",
        %{"prompt" => prompt, "schema_key" => keys, "schema_type" => types},
        socket
      ) do
    output_schema =
      List.zip([keys, types])
      |> Enum.map(fn {key, type} -> {String.to_atom(key), String.to_atom(type)} end)

    {:noreply, socket |> assign(:prompt, prompt) |> assign(:output_schema, output_schema)}
  end

  def render(assigns) do
    ~H"""
    <script src="https://cdn.tailwindcss.com">
    </script>
    <link
      rel="stylesheet"
      href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.6.0/css/all.min.css"
    />

    <style>
      select {
        background: url(data:image/svg+xml;base64,PHN2ZyBpZD0iTGF5ZXJfMSIgZGF0YS1uYW1lPSJMYXllciAxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0Ljk1IDEwIj48ZGVmcz48c3R5bGU+LmNscy0xe2ZpbGw6I2ZmZjt9LmNscy0ye2ZpbGw6IzQ0NDt9PC9zdHlsZT48L2RlZnM+PHRpdGxlPmFycm93czwvdGl0bGU+PHJlY3QgY2xhc3M9ImNscy0xIiB3aWR0aD0iNC45NSIgaGVpZ2h0PSIxMCIvPjxwb2x5Z29uIGNsYXNzPSJjbHMtMiIgcG9pbnRzPSIxLjQxIDQuNjcgMi40OCAzLjE4IDMuNTQgNC42NyAxLjQxIDQuNjciLz48cG9seWdvbiBjbGFzcz0iY2xzLTIiIHBvaW50cz0iMy41NCA1LjMzIDIuNDggNi44MiAxLjQxIDUuMzMgMy41NCA1LjMzIi8+PC9zdmc+) no-repeat 95% 50%;
        -moz-appearance: none;
        -webkit-appearance: none;
        appearance: none;
        padding: 5px 10px;
        width: 150px;
        border-radius: 5px;
        border: 1px solid #ccc;
        height: 42px;
        background-color: white;
      }
    </style>

    <div class="flex flex-col h-screen bg-white text-black max-h-screen">
      <!-- Model Selection -->
      <div class="w-full py-2 px-4 bg-zinc-100 border-b border-gray-300 grid grid-cols-3 items-center">
        <div />
        <div class="flex justify-center">
          <div class="flex justify-start items-center bg-gradient-to-r from-red-400/30 via-purple-400/20 via-20% to-white rounded-lg p-2 pl-4 pr-16 border border-gray-300 animate-gradient">
            <span class="text-3xl font-bold text-white">🍓</span>
            <img src="https://hexdocs.pm/elixir/assets/logo.png" alt="Elixir" class="h-8 ml-1" />
            <span class="ml-6 text-lg font-medium text-gray-700">Structured Outputs <span class="text-gray-400">w/</span> Reasoning</span>
          </div>
        </div>
        <style>
          @keyframes gradient {
            0% {background-position: 0% 50%;}
            50% {background-position: 100% 50%;}
            100% {background-position: 0% 50%;}
          }
          .animate-gradient {
            background-size: 200% 200%;
            animation: gradient 5s ease infinite;
          }
        </style>
        <div class="flex justify-end">
          <form phx-change="select_model" class="flex items-center space-x-3">
            <label class="text-sm font-medium text-gray-700">Model:</label>
            <select
              class="border border-gray-300 rounded-md p-2 text-gray-700 focus:ring focus:ring-gray-400 transition duration-200 ease-in-out text-sm"
              name="model"
            >
              <option
                :for={model <- @models}
                selected={model == @selected_model}
                value={model}
                class="bg-gray-200"
              >
                <%= model %>
              </option>
            </select>
          </form>
        </div>
      </div>

      <div class="grid grid-cols-3 gap-4 p-4 flex-1 min-h-0">
        <.settings_panel {assigns} />
        <.messages_panel {assigns} messages={@cot_messages}>
          <:title>
            <%= @selected_model %> <span class="font-normal italic">with</span>
            Instructor.Extras.ChainOfThought
          </:title>
        </.messages_panel>
        <.messages_panel {assigns} messages={@messages}>
          <:title>
            <%= @selected_model %>
          </:title>
        </.messages_panel>
      </div>
    </div>
    """
  end

  def settings_panel(assigns) do
    ~H"""
    <div class="flex flex-col bg-gray-100 rounded-lg border border-gray-300 shadow-md overflow-hidden">
      <h2 class="text-lg font-semibold p-3 bg-gray-200 text-gray-700 border-b border-gray-300">
        Settings
      </h2>
      <form
        class="p-3 flex-1 overflow-y-auto bg-zinc-50"
        phx-submit="send_message"
        phx-change="update_settings"
      >
        <div class="flex flex-col">
          <label for="prompt" class="mb-2 font-medium text-gray-700">Prompt</label>
          <textarea
            id="prompt"
            name="prompt"
            class="w-full p-2 border border-gray-300 rounded-md"
            rows="16"
          ><%= @prompt %></textarea>
        </div>
        <div class="flex flex-col mt-4">
          <label for="output_schema" class="mb-2 font-medium text-gray-700">Output Schema</label>
          <div class="flex flex-col space-y-2" id="output_schema">
            <%= for {{key, type}, idx} <- Enum.with_index(@output_schema) do %>
              <div class="flex items-center space-x-2">
                <input
                  type="text"
                  name="schema_key[]"
                  value={key}
                  class="flex-1 p-2 border border-gray-300 rounded-md"
                  placeholder="Key"
                />
                <select name="schema_type[]" class="">
                  <%= for option <- [:string, :integer, :float, :boolean, :decimal] do %>
                    <option value={option} selected={type == option}>
                      <%= option %>
                    </option>
                  <% end %>
                </select>
                <button
                  type="button"
                  phx-click="remove_schema_field"
                  phx-value-idx={idx}
                  class="px-2 py-1 text-gray-400 hover:text-gray-500 hover:bg-gray-100 rounded-md"
                >
                  <i class="fas fa-trash-alt"></i>
                </button>
              </div>
            <% end %>
          </div>
          <button
            type="button"
            phx-click="add_schema_field"
            class="mt-2 self-start px-3 py-1 bg-gray-200 text-gray-700 rounded-md hover:bg-gray-300 transition duration-300 ease-in-out flex items-center border border-gray-300"
          >
            <i class="fas fa-plus mr-2"></i> Add Field
          </button>
        </div>
        <div class="flex justify-end">
          <button type="submit" class="mt-4 bg-blue-500 text-white px-4 py-2 rounded-md">Send</button>
        </div>
      </form>
    </div>
    """
  end

  def messages_panel(assigns) do
    ~H"""
    <div class="flex flex-col bg-gray-100 rounded-lg border border-gray-300 shadow-md overflow-hidden">
      <h2 class="text-lg font-semibold p-3 bg-gray-200 text-gray-700 border-b border-gray-300">
        <%= render_slot(@title) %>
      </h2>
      <div class="p-3 flex-1 overflow-y-auto bg-zinc-50">
        <div class="space-y-4 overflow-y-scroll min-h-0">
          <%= for message <- @messages.result do %>
            <%= case message do %>
              <% %Instructor.Extras.ChainOfThought.ReasoningStep{content: content, title: title} -> %>
                <div class="bg-white rounded-lg p-3 border border-gray-300 border-l-4 border-l-blue-500 ml-4">
                  <div class="message-content">
                    <h3 class="text-sm text-gray-600 mb-1">
                      <span class="font-bold text-gray-900">Reasoning Step</span> — <%= title %>
                    </h3>
                    <p class="text-gray-700 text-sm"><%= content %></p>
                  </div>
                </div>
              <% _ -> %>
                <div class="bg-white rounded-lg p-3 border border-gray-300">
                  <h3 class="font-bold text-sm text-gray-700 mb-1">Final Answer</h3>
                  <div class="message-content">
                    <pre class="text-gray-700 text-sm whitespace-pre-wrap"><%= inspect(message, pretty: true, width: 50) %></pre>
                  </div>
                </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

PhoenixPlayground.start(live: DemoLive, live_reload: false)
