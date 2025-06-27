defmodule Hermes.Server.Supervisor do
  @moduledoc """
  Supervisor for MCP server processes.

  This supervisor manages the lifecycle of an MCP server, including:
  - The Base server process that handles MCP protocol
  - The transport layer (STDIO, StreamableHTTP, or SSE)
  - Session supervisors for StreamableHTTP transport

  The supervision strategy is `:one_for_all`, meaning if any child
  process crashes, all processes are restarted to maintain consistency.

  ## Conditional Startup

  The supervisor intelligently handles startup based on transport type:

  - **STDIO transport**: Always starts
  - **StreamableHTTP/SSE transport**: Conditional startup based on:
    1. Explicit `:start` option in transport config (highest priority)
    2. `HERMES_MCP_SERVER` environment variable present
    3. `PHX_SERVER` environment variable present, for phoenix apps using releases
    4. Phoenix `:serve_endpoints` internalr runtime config (usage with `mix phx.server`)
    5. Default: `true` (starts by default in production releases)

  This ensures MCP servers start correctly in all environments:
  - Mix releases: Use `PHX_SERVER=true` or `HERMES_MCP_SERVER=true`
  - Development: Use `mix phx.server`
  - Tests/Tasks: Servers don't start unless explicitly configured

  ## Configuration Examples

  ```elixir
  # Force start with transport option (highest priority)
  {MyServer, transport: {:streamable_http, start: true}}

  # Control via environment variables (works in releases)
  PHX_SERVER=true ./my_app start
  ```

  ## Supervision Tree

  For STDIO transport:
  ```
  Supervisor
  ├── Base Server
  └── STDIO Transport
  ```

  For StreamableHTTP transport:
  ```
  Supervisor
  ├── Session.Supervisor
  ├── Base Server
  └── StreamableHTTP Transport
  ```
  """

  use Supervisor, restart: :permanent

  alias Hermes.Server.Base
  alias Hermes.Server.Session
  alias Hermes.Server.Transport.SSE
  alias Hermes.Server.Transport.STDIO
  alias Hermes.Server.Transport.StreamableHTTP

  @type sse :: {:sse, keyword()}
  @type stream_http :: {:streamable_http, keyword()}

  @type transport :: :stdio | stream_http | sse | StubTransport

  @type start_option :: {:transport, transport} | {:name, Supervisor.name()} | {:session_idle_timeout, pos_integer()}

  @doc """
  Starts the server supervisor.

  ## Parameters

    * `server` - The module implementing `Hermes.Server`
    * `opts` - Options including:
      * `:transport` - Transport configuration (required)
      * `:name` - Supervisor name (optional, defaults to registered name)
      * `:registry` - The custom registry to use to manage processes names (defaults to `Hermes.Server.Registry`)
      * `:session_idle_timeout` - Time in milliseconds before idle sessions expire (default: 30 minutes)

  ## Examples

      # Start with STDIO transport
      Hermes.Server.Supervisor.start_link(MyServer, [], transport: :stdio)

      # Start with StreamableHTTP transport
      Hermes.Server.Supervisor.start_link(MyServer, [],
        transport: {:streamable_http, port: 8080}
      )
      
      # With custom session timeout (15 minutes)
      Hermes.Server.Supervisor.start_link(MyServer, [],
        transport: {:streamable_http, port: 8080},
        session_idle_timeout: :timer.minutes(15)
      )
  """
  @spec start_link(server :: module, list(start_option)) :: Supervisor.on_start()
  def start_link(server, opts) when is_atom(server) and is_list(opts) do
    registry = Keyword.get(opts, :registry, Hermes.Server.Registry)
    name = Keyword.get(opts, :name, registry.supervisor(server))
    opts = Keyword.merge(opts, module: server, registry: registry)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :module)
    transport = normalize_transport(Keyword.fetch!(opts, :transport))
    registry = Keyword.fetch!(opts, :registry)

    if should_start?(transport) do
      {layer, transport_opts} = parse_transport_child(transport, server, registry)

      server_name = registry.server(server)
      server_transport = [layer: layer, name: transport_opts[:name]]

      server_opts = [
        module: server,
        name: server_name,
        transport: server_transport,
        registry: registry
      ]

      server_opts =
        if timeout = Keyword.get(opts, :session_idle_timeout) do
          Keyword.put(server_opts, :session_idle_timeout, timeout)
        else
          server_opts
        end

      children = [
        {Session.Supervisor, server: server, registry: registry},
        {Base, server_opts},
        {layer, transport_opts}
      ]

      Supervisor.init(children, strategy: :one_for_all)
    else
      :ignore
    end
  end

  defp normalize_transport(t) when t in [:stdio, StubTransport], do: t
  defp normalize_transport(t) when t in ~w(sse streamable_http)a, do: {t, []}
  defp normalize_transport({t, opts}) when t in ~w(sse streamable_http)a, do: {t, opts}

  if Mix.env() == :test do
    defp parse_transport_child(StubTransport = kind, server, registry) do
      name = registry.transport(server, kind)
      opts = [name: name, server: server, registry: registry]
      {kind, opts}
    end
  end

  defp parse_transport_child(:stdio, server, registry) do
    name = registry.transport(server, :stdio)
    opts = [name: name, server: server, registry: registry]
    {STDIO, opts}
  end

  defp parse_transport_child({:streamable_http, opts}, server, registry) do
    name = registry.transport(server, :streamable_http)
    opts = Keyword.merge(opts, name: name, server: server, registry: registry)
    {StreamableHTTP, opts}
  end

  defp parse_transport_child({:sse, opts}, server, registry) do
    name = registry.transport(server, :sse)
    opts = Keyword.merge(opts, name: name, server: server, registry: registry)
    {SSE, opts}
  end

  if Mix.env() == :test do
    defp should_start?(StubTransport), do: true
  end

  defp should_start?(:stdio), do: true

  defp should_start?({transport, opts}) when transport in ~w(sse streamable_http)a do
    start? = Keyword.get(opts, :start)
    if is_nil(start?), do: http_server_running?(), else: start?
  end

  defp http_server_running? do
    cond do
      System.get_env("HERMES_MCP_SERVER") -> true
      System.get_env("PHX_SERVER") -> true
      true -> check_phoenix_config()
    end
  end

  defp check_phoenix_config do
    phoenix_start? = Application.get_env(:phoenix, :serve_endpoints)

    if is_nil(phoenix_start?), do: true, else: phoenix_start?
  end
end
