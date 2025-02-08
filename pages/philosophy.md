# Philosophy & Motivations

Instructor is simple library that allows you to maximally leverage large language models (LLMs).
It acts as your bridge between [Karpathy's Software 1.0 and Software 2.0](https://karpathy.medium.com/software-2-0-a64152b37c35).

Software 1.0 is the world we're all used to. 
It's datastructures, databases, algorithms, code.

Software 2.0 on the other hand is neural networks.
They're models to problems for which it's easier to gather examples of desired behavior than describe how to produce it.

## A New Modality

Software 2.0, as it exists today operates in the modality of text, images, and audio.
All modalities that have been traditionally very difficult to deal with in Software 1.0.

We now have these things called LLMs.
For the first time we can solve non-trivial `f(text) -> text` problems.

```

  llm("Recipe for a banana smoothie") -> """
    A banana smoothie is a delicious and nutritious treat that's quite easy to make. Here's a simple recipe for you:

    Ingredients:

    2 ripe bananas
    1 cup milk (you can use almond, soy, or cow's milk)
    1/2 cup Greek yogurt (optional, for extra creaminess)
    1-2 tablespoons honey or maple syrup (adjust according to taste)
    A pinch of cinnamon (optional)
    Ice cubes (optional, for a colder smoothie)
    Instructions:

    Peel the bananas and place them in a blender.
    Add the milk, Greek yogurt (if using), honey/maple syrup, and cinnamon.
    Add a few ice cubes if you prefer a colder smoothie.
    Blend until smooth and creamy. If the smoothie is too thick, you can add a little more milk to reach your desired consistency.
    Taste and adjust the sweetness if necessary.
    Pour into glasses and serve immediately.

    Enjoy your banana smoothie!
  """

```

However from a Software 1.0 perspective, this isn't terribly useful.
Remember, Software 1.0 doesn't have robust, non trivial semantic text processing.
We can pretty easily create the function's arguments, but are you sure you can robustly parse the output? Unlikely.

## LLMs aren't only for chatbots

Over the past year you've probably noticed that every LLM company produces some variation of a chatbot -
Chat with GPT, Chat with your PDF, Chat with your AI Girlfriend.

This makes sense, when you think about it.
We're really good at creating strings in Software 1.0 from structured data, but we're terrible at creating structured data from strings.
Nor are we any good any good at interpreting the semantic meaning of strings.

Therefore, it only makes sense to design experiences where we present them to the user for interpretation.
Alas, our ubiquitous chatbot interface.

But it doesn't have to be that way. 
What if we can get our LLMs to respond with structured data?
That'd give us the all our domains and ranges covered,

```
  f(text) -> text
  f(data_structure |> to_string) -> text
  f(data_structure |> to_string) -> data_structure
```

With such a capability, you would have full bidirectional interoperability between software 1.0 and software 2.0. 
That's what Instructor provides. 

## cast_all\2, It's just Ecto baby

Now to do this we need to give the LLM a schema that it has to conform to in its output text. 
If we can guarantee that it outputs JSON that matches this schema, we can treat it as any other user data we're used to in Elixir.

That's why, we figure, let's just build this on top of Ecto. It's already in your app after all.
You already know how to use it.
It already provides a robust validations API.
Let's just treat the LLM as if it's one of your users, submitting data through a form.

```elixir
defmodule Recipe do
  use Ecto.Schema

  @doc """
    Our AI generated delicious recipe.
  """
  @primary_key false
  embedded_schema do 
    field :title, :string
    field :cook_time, :integer
    field :steps, {:array, :string}
    embeds_many :ingredients, Ingredients, primary_key: false do
      field :name, :string
      field :quantity, :decimal
      field :unit, :string
    end
  end
end
```

From this instructor takes your ecto schema, converts it into a JSON schema, and passes it on to the LLM.
It uses clever techniques like function calling and BNF grammar sampling to ensure that we get back a result that is exactly matching our Ecto schema.
At which point it's all just Ecto code.
We cast the fields, we do the validations, and we return the result back to you.

```elixir
Instructor.chat_completion(
  model: "gpt-4o-mini",
  response_model: Recipe,
  messages: [
    %{ role: "user", content: "Give me a recipe for a banana smoothie" }
  ]
)

# => {:ok, %Recipe{title: "Banana smoothie", cook_time: 15, steps: [...]}
```

Instructor makes Ecto is our interchange format between Software 1.0 and 2.0.
Perfect because Ecto is a mainstay in the ecosystem and compatible with so many other libraries. 

## Used Anywhere where Ecto is used

Now this is a neat capability, but you may be thinking, where can I use this?  
This is Virgin Territory. We've never had this capability. It is a new modality in computing.
It will require a bit of imagination.
A good heuristic to start with is, "wherever I use Ecto, I can use Instructor." 

```
  user -> instructor -> code
  code -> instructor -> code
  code -> instructor -> user
```

There is a 40Gb LLM file sitting on Huggingface that encodes the entirety of human knowledge, you now have a query interface for it.

## Where to go from here?

First, go check out the [Introduction to Instructor Tutorial](#) where we go over the user guide of how to get up and running with instructor.
Then, checkout the [cookbooks](#) to see various techniques of how to best leverage instructor in common usecases.
