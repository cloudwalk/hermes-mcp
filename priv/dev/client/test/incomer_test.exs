defmodule IncomerTest do
  use ExUnit.Case
  doctest Incomer

  test "greets the world" do
    assert Incomer.hello() == :world
  end
end
