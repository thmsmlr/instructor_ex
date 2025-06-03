defmodule Instructor.Types.Duration do
  @moduledoc """
  Custom Ecto type for handling ISO8601 duration strings.

  This type properly parses ISO8601 duration format (e.g., "PT1H30M5S")
  instead of relying on the database layer.
  """
  use Ecto.Type
  use Instructor.EctoType

  @impl true
  def type, do: :string

  def to_json_schema() do
    %{
      type: "string",
      description: "A valid ISO8601 duration, e.g. PT3M14S",
      format: "duration",
      pattern: "^P(?:(\\d+)Y)?(?:(\\d+)M)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+(?:\\.\\d+)?)S)?)?$"
    }
  end

  @impl true
  def cast(duration) when is_binary(duration) do
    case Duration.from_iso8601(duration) do
      {:ok, duration} -> {:ok, duration}
      {:error, _} -> :error
    end
  end

  @impl true
  def cast(%Duration{} = duration), do: {:ok, duration}
  def cast(_), do: :error

  @impl true
  def load(data) when is_map(data) do
    data =
      for {key, val} <- data do
        {String.to_existing_atom(key), val}
      end

    {:ok, struct!(Duration, data)}
  end

  @impl true
  def dump(%URI{} = uri), do: {:ok, Map.from_struct(uri)}
  def dump(_), do: :error
end
