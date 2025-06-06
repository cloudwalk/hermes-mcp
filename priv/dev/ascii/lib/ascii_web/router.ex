defmodule AsciiWeb.Router do
  use AsciiWeb, :router

  alias Hermes.Server.Transport.StreamableHTTP

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AsciiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :api

    forward "/mcp", StreamableHTTP.Plug, server: Ascii.MCPServer
  end

  scope "/", AsciiWeb do
    pipe_through :browser

    live "/", AsciiLive, :index
  end
end
