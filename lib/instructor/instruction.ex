if Code.ensure_loaded?(Flint.Schema) do
  defmodule Instructor.Instruction do
    use Flint.Extension

    attribute(:stream, default: false, validator: &is_boolean/1)
    attribute(:validation_context, default: %{}, validator: &is_map/1)
    attribute(:mode, default: :tools, validator: &Kernel.in(&1, [:tools, :json, :md_json]))
    attribute(:max_retries, default: 0, validator: &is_integer/1)
    attribute(:system_prompt, validator: &is_binary/1)
    attribute(:model, validator: &is_binary/1)
    attribute(:array, default: false, validator: &is_boolean/1)
    attribute(:template)

    option(:doc, default: "", validator: &is_binary/1, required: false)

    defmacro __using__(_opts) do
      quote do
        use Instructor.Validator
        require EEx

        def render_template(assigns) do
          EEx.eval_string(__MODULE__.__schema__(:template), assigns: assigns)
        end

        def chat_completion(messages, opts \\ []) do
          opts =
            Keyword.validate!(opts,
              stream: __MODULE__.__schema__(:stream),
              validation_context: __MODULE__.__schema__(:validation_context),
              mode: __MODULE__.__schema__(:mode),
              max_retries: __MODULE__.__schema__(:max_retries),
              model: __MODULE__.__schema__(:model)
            )

          messages = if Keyword.keyword?(messages), do: [messages], else: messages

          messages =
            for message <- messages do
              case message do
                %{role: _role, content: _content} ->
                  message

                _ ->
                  %{
                    role: "user",
                    content:
                      if(__MODULE__.__schema__(:template),
                        do: render_template(message),
                        else: message
                      )
                  }
              end
            end

          messages =
            if __MODULE__.__schema__(:system_prompt) do
              [%{role: "system", content: __MODULE__.__schema__(:system_prompt)} | messages]
            else
              messages
            end

          response_model =
            if __MODULE__.__schema__(:array), do: {:array, __MODULE__}, else: __MODULE__

          opts = ([messages: messages, response_model: response_model] ++ opts)
          Instructor.chat_completion(opts)
        end

        @impl true
        def validate_changeset(changeset, context \\ %{}) do
          __MODULE__
          |> struct!()
          |> changeset(changeset, Enum.into(context, []))
        end

        defoverridable validate_changeset: 1, validate_changeset: 2
      end
    end
  end
end
