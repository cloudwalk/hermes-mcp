defmodule Hermes.Server.Supervisor do
  @moduledoc false

  use Supervisor, restart: :permanent

  alias Hermes.Server.Base
  alias Hermes.Server.Session
  alias Hermes.Server.Transport.SSE
  alias Hermes.Server.Transport.STDIO
  alias Hermes.Server.Transport.StreamableHTTP

  @type sse :: {:sse, keyword()}
  @type stream_http :: {:streamable_http, keyword()}

  @type transport :: :stdio | stream_http | sse | StubTransport

  @type start_option ::
          {:transport, transport}
          | {:name, Supervisor.name()}
          | {:session_idle_timeout, pos_integer() | nil}
          | {:request_timeout, pos_integer() | nil}
          | {:server_name, GenServer.name() | nil}

  @doc """
  Starts the server supervisor.

  ## Parameters

    * `server` - The module implementing `Hermes.Server`
    * `opts` - Options including:
      * `:transport` - Transport configuration (required)
      * `:name` - Supervisor name (optional, defaults to registered name)
      * `:registry` - The custom registry to use to manage processes names (defaults to `Hermes.Server.Registry`)
      * `:session_idle_timeout` - Time in milliseconds before idle sessions expire (default: 30 minutes)
      * `:request_timeout` - Time limit in miliseconds for server requests timeout (defaults to 30s)
      * `:server_name` - Custom server name, non derived from the `server_module`

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

      server_name = registry.server(opts[:server_name] || server)
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

      request_timeout = Keyword.get(opts, :request_timeout, to_timeout(second: 30))

      task_supervisor = registry.task_supervisor(server)

      transport_opts =
        Keyword.merge(transport_opts,
          request_timeout: request_timeout,
          task_supervisor: task_supervisor
        )

      children = [
        {Task.Supervisor, name: task_supervisor},
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
    IO.warn(
      "The :sse transport option is deprecated as of MCP specification 2025-03-26. " <>
        "Please use {:streamable_http, opts} instead. " <>
        "The SSE transport is maintained only for backward compatibility with MCP protocol version 2024-11-05.",
      []
    )

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
