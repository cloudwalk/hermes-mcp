defmodule OauthExample.Router do
  use Plug.Router

  alias Hermes.Server.Transport.StreamableHTTP

  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: JSON
  )

  plug(:match)
  plug(:dispatch)

  # Forward MCP requests to the StreamableHTTP plug with authorization
  forward("/mcp", to: StreamableHTTP.Plug, init_opts: [server: OauthExample.Server])

  # Health check endpoint (no auth required)
  get "/health" do
    send_resp(conn, 200, JSON.encode!(%{status: "ok"}))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
