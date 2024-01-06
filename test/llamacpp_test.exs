Code.compiler_options(ignore_module_conflict: true, docs: true, debug_info: true)

defmodule LlamaCppTest do
  use ExUnit.Case, async: false

  setup_all do
    Application.put_all_env(
      instructor: [
        adapter: Instructor.Adapters.Llamacpp
      ],
    )
    {:ok, state: :ok}
  end

  @tag :skip
  test "spam predicition example" do
    defmodule EmailSpamPrediction do
      use Ecto.Schema

      @doc """
      Determine whether the provided text is spam or not.
      """
      @primary_key false
      embedded_schema do
        field(:is_spam?, :boolean)
        field(:reason, :string)
      end
    end

    predict_spam = fn text ->
      Instructor.chat_completion(
        response_model: EmailSpamPrediction,
        messages: [
          %{role: "user", content: "Classify the following email as spam or not: #{text}"}
        ]
      )
    end

    result =
      predict_spam.("Hello, I'm a Nigerian prince and I would like to send you some money.")

    assert {:ok, _} = result
  end
end
