defmodule Instructor.Extras.ChainOfThought do
  defmodule ReasoningStep do
    use Ecto.Schema

    @doc """
    For each step, provide a title that describes what you're doing in that step, along with the content.
    Decide if you need another step or if you're ready to give the final answer.
    Respond in JSON format with 'title', 'content', and 'next_action' (either 'continue' or 'final_answer') keys.
    """
    @primary_key false
    embedded_schema do
      field(:title, :string)
      field(:content, :string)
      field(:next_action, Ecto.Enum, values: [:final_answer, :continue])
    end
  end

  def chat_completion(params, config \\ nil) do
    reasoning_steps = Keyword.pop(params, :reasoning_steps, 3)
    response_model = params[:response_model]

    initial_messages =
      [
        %{
          role: "system",
          content: """
          You are an expert AI assistant that explains your reasoning step by step.
          For each step, provide a title that describes what you're doing in that step, along with the content.
          Decide if you need another step or if you're ready to give the final answer.
          Respond in JSON format with 'title', 'content', and 'next_action' (either 'continue' or 'final_answer') keys.
          USE AS MANY REASONING STEPS AS POSSIBLE.
          AT LEAST 3.
          # ... (rest of the system message)
          """
        }
      ] ++
        params[:messages] ++
        [
          %{
            role: "assistant",
            content: """
            Thank you! I will now think step by step following my instructions, starting at the beginning after decomposing the problem.
            """
          }
        ]

    params = Keyword.put(params, :messages, initial_messages)
    params = Keyword.put(params, :response_model, ReasoningStep)

    Stream.resource(
      fn -> {params, 0} end,
      fn
        :halt ->
          {:halt, nil}

        {:final_answer, params} ->
          new_messages =
            params[:messages] ++
              [
                %{
                  role: "user",
                  content: """
                  Please provide the final answer based solely on your reasoning above.
                  Only provide the text response without any titles or preambles.
                  Retain any formatting as instructed by the original prompt, such as exact formatting for free response or multiple choice.
                  """
                }
              ]

          params = Keyword.put(params, :messages, new_messages)
          params = Keyword.put(params, :response_model, response_model)
          {:ok, final_answer} = Instructor.chat_completion(params, config)
          {[{:final_answer, final_answer}], :halt}

        {params, step_count} ->
          case Instructor.chat_completion(params, config) do
            {:ok, %ReasoningStep{} = step} ->
              new_messages =
                params[:messages] ++
                  [
                    %{
                      role: "assistant",
                      content: step |> Map.from_struct() |> Jason.encode!()
                    }
                  ]

              params = Keyword.put(params, :messages, new_messages)

              acc =
                case step.next_action do
                  :final_answer ->
                    {:final_answer, params}

                  :continue ->
                    {params, step_count + 1}
                end

              {[step], acc}

            {:error, reason} ->
              IO.inspect(reason, label: "ERROR")
              {:halt, {params, step_count}}
          end
      end,
      fn _ -> nil end
    )
    |> Stream.transform(0, fn
      {:final_answer, final_answer}, _step_count ->
        {[final_answer], :halt}

      step, step_count when step_count < reasoning_steps ->
        {[step], step_count + 1}

      _step, _step_count ->
        {[{:error, "No final answer within #{reasoning_steps} reasoning steps"}], :halt}
    end)
  end
end
