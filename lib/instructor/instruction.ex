defmodule Instructor.Union do
  use Flint.Type, extends: Flint.Types.Union
  @behaviour Instructor.EctoType

  @impl true
  def to_json_schema(%{types: types}) when is_list(types) do
    %{
      "oneOf" => Enum.map(types, &Instructor.EctoType.for_type/1)
    }
  end
end

defmodule Instructor.Instruction do
  use Flint.Extension

  attribute :stream, default: false, validator: &is_boolean/1
  attribute :validation_context, default: %{}, validator: &is_map/1
  attribute :mode, default: :tools, validator: &Kernel.in(&1, [:tools, :json, :md_json])
  attribute :max_retries, default: 0, validator: &is_integer/1
  attribute :system_prompt, validator: &is_binary/1
  attribute :model, validator: &is_binary/1
  attribute :array, default: false, validator: &is_boolean/1
  attribute :template

  option :doc, default: "", validator: &is_binary/1, required: false
  option :llm_verify, required: false

  @impl true
  def changeset(changeset, bindings \\ []) do
    module = changeset.data.__struct__
    env = Module.concat(module, Env) |> apply(:env, [])

    quoted_statements =
      module.__schema__(:extra_options)
      |> Enum.map(fn {field, opts} -> {field, Keyword.get(opts, :llm_verify)} end)
      |> Enum.reject(fn
        {_k, nil} -> true
        other -> false
      end)

    for {field, quoted_statement} <- quoted_statements, reduce: changeset do
      changeset ->
        bindings = bindings ++ Enum.into(changeset.changes, [])

        case eval_quoted(quoted_statement, bindings, env) do
          {:ok, {<<statement::binary>>, _bindings}} ->
            model = bindings[:model] || module.__schema__(:model)
            opts = if model, do: [model: model], else: []
            Instructor.Validator.validate_with_llm(changeset, field, statement, opts)

          {:ok, {_other, _bindings}} ->
            raise ArgumentError,
                  "Expression for `:llm_verify` in field #{inspect(field)} must return a binary!"

          _ ->
            raise ArgumentError,
                  "Failed to evaluate expression for option `:llm_verify` in field #{inspect(field)}"
        end
    end
  end

  defmacro __using__(_opts) do
    quote do
      use Instructor.Validator
      alias Instructor.Union

      def render_template(assigns) do
        EEx.eval_string(__MODULE__.__schema__(:template), assigns: assigns)
      end

      def chat_completion(messages, opts \\ []) do
        {stream, opts} = Keyword.pop(opts, :stream, __MODULE__.__schema__(:stream))

        {validation_context, messages, opts} =
          cond do
            Keyword.has_key?(opts, :validation_context) ->
              {validation_context, opts} = Keyword.pop!(opts, :validation_context)
              {validation_context, messages, opts}

            Keyword.has_key?(messages, :validation_context) ->
              {validation_context, messages} = Keyword.pop!(messages, :validation_context)
              {validation_context, messages, opts}

            true ->
              {__MODULE__.__schema__(:validation_context), messages, opts}
          end

        {mode, opts} = Keyword.pop(opts, :mode, __MODULE__.__schema__(:mode))

        {max_retries, opts} =
          Keyword.pop(opts, :max_retries, __MODULE__.__schema__(:max_retries))

        {model, opts} = Keyword.pop(opts, :model, __MODULE__.__schema__(:model))

        {config, opts} = Keyword.split(opts, [:api_key, :api_url, :http_options])

        settings =
          [
            stream: stream,
            validation_context: validation_context,
            mode: mode,
            max_retries: max_retries,
            model: model
          ]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

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

        opts = [messages: messages, response_model: response_model] ++ settings ++ opts
        Instructor.chat_completion(opts, config)
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
