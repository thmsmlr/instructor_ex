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
    |> Stream.filter(fn line -> line != "" end)
    |> Stream.transform(
      fn -> {:root, ""} end,
      fn
        "data: [DONE]" <> _, {:root, ""} ->
          {:halt, {:root, ""}}

        "data: " <> data, {:root, ""} ->
          {[{:ok, Jason.decode!(data)}], {:root, ""}}

        line, {_, acc} ->
          {[], {:json, acc <> line}}
      end,
      fn
        {:json, acc} ->
          {[{:error, Jason.decode!(acc)}], {:root, ""}}

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
end
