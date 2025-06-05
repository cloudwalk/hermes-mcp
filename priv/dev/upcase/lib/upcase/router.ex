defmodule Upcase.Router do
  use Plug.Router

  alias Hermes.Server.Transport.StreamableHTTP

  plug Plug.Logger
  plug :match
  plug :dispatch

  forward "/mcp", to: StreamableHTTP.Plug, init_opts: [server: Upcase.Server]

  match _ do
    send_resp(conn, 404, "not found")
  end
end
