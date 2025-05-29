defmodule Upcase.HTTP do
  @moduledoc """
  HTTP endpoint for the Upcase MCP server using Streamable HTTP transport.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  forward("/mcp",
    to: Hermes.Server.Transport.StreamableHTTP.Plug,
    init_opts: [transport: Upcase.ServerHTTP]
  )

  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, JSON.encode!(%{error: "Not found"}))
  end
end
