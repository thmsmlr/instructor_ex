defmodule Instructor.Instruction do
  use Flint.Extension

  attribute :stream, default: false, validator: &is_boolean/1
  attribute :validation_context, default: %{}, validator: &is_map/1

  attribute :mode,
    default: :structured_output,
    validator: &Kernel.in(&1, [:tools, :json, :md_json, :structured_output, :json_schema])

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
        _ -> false
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

  def pop_from_any(keywords, key, default \\ nil) do
    index = Enum.find_index(keywords, &Keyword.has_key?(&1, key))

    if is_nil(index) do
      {default, keywords}
    else
      {value, new_kw_list} = Enum.at(keywords, index) |> Keyword.pop!(key)
      {value, List.replace_at(keywords, index, new_kw_list)}
    end
  end

  defmacro __using__(opts) do
    template_engine = Keyword.get(opts, :template_engine) |> Macro.expand_literals(__CALLER__)

    quote do
      use Instructor.Validator
      alias Instructor.Union

      def render_template(template, assigns) do
        case unquote(template_engine) do
          nil ->
            EEx.eval_string(template, assigns: assigns)

          {mod, fun} = engine ->
            apply(mod, fun, [template, assigns])
        end
      end

      def chat_completion(messages, opts \\ []) do
        {[messages, opts], params} =
          Enum.reduce(
            [
              :stream,
              :validation_context,
              :template,
              :mode,
              :max_retries,
              :model,
              :system_prompt,
              :array,
              :api_key,
              :api_url,
              :http_options,
              :adapter,
              :after_request
            ],
            {[messages, opts], []},
            fn key, {kwords, bindings} ->
              default =
                case __MODULE__.__schema__(key) do
                  {:error, _} ->
                    nil

                  other ->
                    other
                end

              {value, kwords} =
                Instructor.Instruction.pop_from_any(kwords, key, default)

              {kwords, [{key, value} | bindings]}
            end
          )

        config =
          Keyword.take(params, [:api_key, :api_url, :http_options, :adapter])
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

        settings =
          [
            stream: params[:stream],
            validation_context: params[:validation_context],
            mode: params[:mode],
            max_retries: params[:max_retries],
            model: params[:model]
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
                    if(params[:template],
                      do: render_template(params[:template], message),
                      else: message
                    )
                }
            end
          end

        messages =
          if params[:system_prompt] do
            [%{role: "system", content: params[:system_prompt]} | messages]
          else
            messages
          end

        response_model =
          if params[:array], do: {:array, __MODULE__}, else: __MODULE__

        opts =
          [messages: messages, response_model: response_model, after_request: params[:after_request]] ++ settings ++ opts

        Instructor.chat_completion(opts, config)
      end

      @impl true
      def validate_changeset(changeset, context \\ %{}) do
        __MODULE__
        |> struct!()
        |> changeset(changeset, Enum.into(context, []))
      end

      defoverridable validate_changeset: 1,
                     validate_changeset: 2,
                     chat_completion: 1,
                     chat_completion: 2
    end
  end
end
