defmodule Instructor.SSEStreamParser do
  @moduledoc false

  def parse(stream) do
    stream
    |> Stream.transform("", fn
      data, acc ->
        {chunks, [remaining]} = (acc <> data) |> String.split("\n", trim: false) |> Enum.split(-1)
        {chunks, remaining}
    end)
    |> Stream.flat_map(fn chunk ->
      chunk
      |> String.split("data: ")
      |> Enum.filter(&String.starts_with?(&1, "{"))
      |> Enum.map(fn json_string ->
        Jason.decode!(json_string)
      end)
    end)
    # |> Stream.each(&IO.inspect/1)
  end
end
