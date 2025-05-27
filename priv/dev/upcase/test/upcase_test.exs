defmodule UpcaseTest do
  use ExUnit.Case
  doctest Upcase

  test "greets the world" do
    assert Upcase.hello() == :world
  end
end
