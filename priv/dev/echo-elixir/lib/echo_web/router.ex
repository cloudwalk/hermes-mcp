defmodule EchoWeb.Router do
  use EchoWeb, :router

  alias Hermes.Server.Transport.SSE

  pipeline :sse do
    plug :accepts, ["json", "event-stream"]
  end

  scope "/mcp" do
    pipe_through :sse

    get "/sse", SSE.Plug, server: EchoMCP.Server, mode: :sse
    post "/message", SSE.Plug, server: EchoMCP.Server, mode: :post
  end
end
