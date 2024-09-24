Mix.install([
  {:phoenix_playground, github: "gmile/phoenix_playground", branch: "handle-async-callback"},
  {:instructor, path: Path.expand("~/code/instructor_ex")}
])

defmodule Recipe do
  use Ecto.Schema

  @doc """
  A recipe with ingredients and instructions.

  Ingredients should include quantity, unit, and name, for example:

  %{
    name: "salt",
    quantity: 1,
    unit: "cup"
  }

  Instructions should include step and optional notes.

  %{
    step: "Mix the water and flour",
  }
  """
  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:description, :string)
    field(:prep_time, :integer)
    field(:cook_time, :integer)
    field(:total_time, :integer)
    field(:servings, :integer)

    embeds_many(:ingredients, Ingredient) do
      field(:name, :string)
      field(:quantity, :decimal)
      field(:unit, :string)
    end

    embeds_many(:instructions, Instruction) do
      field(:step, :string)
    end
  end
end

defmodule StreamingUILive do
  use Phoenix.LiveView
  use Phoenix.Component

  alias Phoenix.LiveView.AsyncResult

  @instructor_config [
    adapter: Instructor.Adapters.OpenAI,
    api_key: System.get_env("OPENAI_API_KEY")
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:prompt, "")
     |> assign(:recipe, AsyncResult.ok(nil))}
  end

  def handle_event("submit", %{"prompt" => prompt}, socket) do
    pid = self()

    {:noreply,
     socket
     |> assign(:prompt, "")
     |> start_async(:generate_recipe, fn ->
       {:ok, recipe} =
         Instructor.chat_completion(
           [
             model: "gpt-4o-mini",
             response_model: {:partial, Recipe},
             stream: true,
             messages: [
               %{role: "user", content: prompt}
             ]
           ],
           @instructor_config
         )
         |> Stream.each(fn {_state, recipe} ->
           send(pid, {:partial, Recipe, recipe})
         end)
         |> Enum.to_list()
         |> List.last()

       recipe
     end)}
  end

  def handle_info({:partial, Recipe, recipe}, socket) do
    # Update the AsyncResult with the new partial recipe, but keep in existing loading state
    {:noreply, assign(socket, :recipe, %{socket.assigns.recipe | result: recipe})}
  end

  def handle_async(:generate_recipe, {:ok, recipe}, socket) do
    {:noreply, assign(socket, :recipe, AsyncResult.ok(recipe))}
  end

  def handle_async(:generate_recipe, {:error, error}, socket) do
    {:noreply, assign(socket, :recipe, AsyncResult.error(error))}
  end

  def search_unsplash(query) do
    Req.get(
      "https://api.unsplash.com/search/photos",
      params: [query: "#{query}", per_page: 1, client_id: System.get_env("UNSPLASH_ACCESS_KEY")]
    )
    |> case do
      {:ok, %Req.Response{body: %{"results" => [%{"urls" => %{"regular" => image_url}}]}}} ->
        image_url

      {:error, error} ->
        IO.inspect(error)
        nil
    end
  end

  def image_for_recipe(%Recipe{name: name} = _recipe) when not is_nil(name) do
    cache_key = {:unsplash_image, name}

    case Process.get(cache_key) do
      nil ->
        image_url = search_unsplash(name)
        Process.put(cache_key, image_url)
        image_url

      cached_url ->
        cached_url
    end
  end

  def image_for_recipe(_), do: ""

  def render(assigns) do
    ~H"""
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.6.0/css/all.min.css" />
    <div class="flex h-screen">
      <div class="w-1/3 pr-8 flex flex-col justify-center items-center px-8 py-16 border-r border-zinc-200">
        <h1 class="text-3xl font-bold mb-6">✨ AI Recipe Generator</h1>
        <form phx-submit="submit" class="mb-6">
          <input
            type="text"
            name="prompt"
            value={@prompt}
            placeholder="What do you want to eat?"
            class="border rounded-lg p-3 w-full mb-4 shadow-sm"
          />
          <button
            type="submit"
            class="bg-blue-500 hover:bg-blue-600 text-white p-3 rounded-lg w-full transition duration-300 ease-in-out"
            disabled={!!@recipe.loading}
          >
            <%= if @recipe.loading, do: "Generating...", else: "Generate Recipe" %>
          </button>
        </form>
      </div>

      <div class="w-2/3 pl-8 flex flex-col justify-center overflow-y-auto bg-zinc-100 px-8 py-16">
        <.recipe {assigns}/>
      </div>
    </div>
    """
  end

  defp recipe(assigns) do
    ~H"""
    <div :if={@recipe.result != nil} class="bg-white shadow-lg rounded-lg overflow-hidden max-w-3xl mx-auto">
      <div class="relative">
        <div class="absolute inset-0 bg-gradient-to-b from-transparent to-black opacity-70"></div>
        <img src={image_for_recipe(@recipe.result)} alt={@recipe.result.name} class="w-full h-64 object-cover" />
        <h2 class="absolute bottom-4 left-4 text-3xl font-bold text-white"><%= @recipe.result.name %></h2>
      </div>

      <div class="p-6">
        <p class="text-gray-600 italic mb-6"><%= @recipe.result.description %></p>

        <div class="flex justify-between items-center mb-6 text-sm text-gray-600">
          <span><i class="fas fa-clock mr-2"></i>Prep: <%= @recipe.result.prep_time %> min</span>
          <span><i class="fas fa-fire mr-2"></i>Cook: <%= @recipe.result.cook_time %> min</span>
          <span><i class="fas fa-utensils mr-2"></i>Total: <%= @recipe.result.total_time %> min</span>
          <span><i class="fas fa-users mr-2"></i>Serves: <%= @recipe.result.servings %></span>
        </div>

        <div class="mb-8">
          <h3 class="text-xl font-semibold mb-4 text-gray-800 border-b pb-2">Ingredients</h3>
          <div class="grid grid-cols-3 gap-2 auto-rows-fr">
            <%= for ingredient <- @recipe.result.ingredients do %>
              <div class="flex items-center h-full">
                <span class="w-6 h-6 bg-gray-200 rounded-full mr-3 flex items-center justify-center text-gray-600 text-xs flex-shrink-0">
                  <%= if ingredient.quantity != nil do %>
                    <%= to_string(ingredient.quantity) %>
                  <% end %>
                </span>
                <span class="text-gray-700 flex-grow"><%= ingredient.unit %> <%= ingredient.name %></span>
              </div>
            <% end %>
          </div>
        </div>

        <div>
          <h3 class="text-xl font-semibold mb-4 text-gray-800 border-b pb-2">Instructions</h3>
          <ol class="space-y-4">
            <%= for {step, index} <- Enum.with_index(@recipe.result.instructions) do %>
              <li class="flex">
                <span class="bg-gray-300 text-gray-700 rounded-full w-8 h-8 flex items-center justify-center mr-4 flex-shrink-0"><%= index + 1 %></span>
                <p class="text-gray-700"><%= step.step %></p>
              </li>
            <% end %>
          </ol>
        </div>
      </div>
    </div>
    """
  end
end

PhoenixPlayground.start(live: StreamingUILive, live_reload: false)
