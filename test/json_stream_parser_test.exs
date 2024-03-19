defmodule JSONStreamParserTest do
  use ExUnit.Case, async: true

  alias Instructor.JSONStreamParser

  def chunkify(obj) do
    obj
    |> Jason.encode!()
    |> String.graphemes()
    |> Enum.chunk_every(10)
    |> Enum.map(&Enum.join/1)
  end

  # TODO: Doesn't work with numbers for some reason, need to dig into Jaxon
  for val <- [true, false, "foobar", nil] do
    test "emits primitive #{inspect(val)} once on completion" do
      result =
        unquote(val)
        |> chunkify()
        |> JSONStreamParser.parse()
        |> Enum.to_list()

      assert [unquote(val)] = result
    end
  end

  test "emits array items one at a time" do
    result =
      ["foo", "bar", "baz"]
      |> chunkify()
      |> JSONStreamParser.parse()
      |> Enum.to_list()

    assert [[], ["foo"], ["foo", "bar"], ["foo", "bar", "baz"]] = result
  end

  test "emits object each key" do
    result =
      %{"foo" => "bar", "baz" => "qux"}
      |> chunkify()
      |> JSONStreamParser.parse()
      |> Enum.to_list()

    assert [
             %{},
             %{"baz" => "qux"},
             %{"foo" => "bar", "baz" => "qux"}
           ] = result
  end

  test "recursively emits array items in object" do
    result =
      %{"foo" => ["bar", "baz"]}
      |> chunkify()
      |> JSONStreamParser.parse()
      |> Enum.to_list()

    assert [
             %{},
             %{"foo" => []},
             %{"foo" => ["bar"]},
             %{"foo" => ["bar", "baz"]}
           ] = result
  end

  test "The big test" do
    result =
      %{"foo" => [%{"bar" => "baz"}, %{"qux" => "quux"}]}
      |> chunkify()
      |> JSONStreamParser.parse()
      |> Enum.to_list()

    assert [
             %{},
             %{"foo" => []},
             %{"foo" => [%{}]},
             %{"foo" => [%{"bar" => "baz"}]},
             %{"foo" => [%{"bar" => "baz"}, %{}]},
             %{"foo" => [%{"bar" => "baz"}, %{"qux" => "quux"}]}
           ] = result
  end
end
