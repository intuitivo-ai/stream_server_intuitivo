defmodule MjpegServerTest do
  use ExUnit.Case
  doctest MjpegServer

  test "greets the world" do
    assert MjpegServer.hello() == :world
  end
end
