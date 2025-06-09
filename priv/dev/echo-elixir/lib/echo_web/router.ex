defmodule EchoWeb.Router do
  use EchoWeb, :router

  alias Hermes.Server.Transport.StreamableHTTP

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :api

    forward "/mcp", StreamableHTTP.Plug, server: EchoMCP.Server
  end
end
