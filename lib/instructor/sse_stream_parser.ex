defmodule Instructor.SSEStreamParser do
  @moduledoc false

  # Yuk, but it works
  def parse(stream) do
    stream
    |> Stream.transform(
      fn -> "" end,
      fn
        chunk, acc ->
          {chunks, [remaining]} =
            (acc <> chunk)
            |> String.split("\n", trim: false)
            |> Enum.split(-1)

          {chunks, remaining}
      end,
      fn acc -> {[acc], nil} end,
      fn _acc -> nil end
    )
    |> Stream.filter(fn line -> String.trim(line) != "" end)
    |> Stream.transform(
      fn -> {:root, ""} end,
      fn
        "data: [DONE]" <> _, {:root, ""} ->
          {:halt, {:root, ""}}

        "data: " <> data, {:root, ""} ->
          {[{:ok, decode_json!(data)}], {:root, ""}}

        "event: " <> _, {_, _} ->
          {[], {:root, ""}}

        line, {_, acc} ->
          {[], {:json, acc <> line}}
      end,
      fn
        {:json, acc} ->
          {[{:error, decode_json!(acc)}], {:root, ""}}

        {:root, ""} ->
          {[], {:root, ""}}
      end,
      fn _acc -> nil end
    )
    |> Stream.map(fn
      {:ok, data} ->
        data

      {:error, error} ->
        raise "Error from LLM: #{inspect(error)}"
    end)
  end

  defp decode_json!(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      {:error, err} -> raise "Error decoding: #{inspect(err)} \n\n #{inspect(data)}"
    end
  end
end
