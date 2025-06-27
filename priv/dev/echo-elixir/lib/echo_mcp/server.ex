defmodule EchoMCP.Server do
  @moduledoc false

  use Hermes.Server, name: "Echo Server", version: Echo.version(), capabilities: [:tools]

  component(EchoMCP.Tools.Echo)
end
