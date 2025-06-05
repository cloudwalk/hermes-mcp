defmodule Hermes.Server.Supervisor do
  @moduledoc false

  use Supervisor, restart: :permanent

  alias Hermes.Server.Base
  alias Hermes.Server.Registry
  alias Hermes.Server.Session
  alias Hermes.Server.Transport.STDIO
  alias Hermes.Server.Transport.StreamableHTTP

  # TODO(zoedsoupe): need to implement backward compatibility with SSE/2024-05-11
  @type sse :: []
  @type stream_http :: []

  @type transport :: :stdio | stream_http | sse
  @type session_mode :: :single | :per_client

  @type start_option ::
          {:transport, transport}
          | {:name, Supervisor.name()}
          | {:session_mode, session_mode}

  @spec start_link(server :: module, init_arg :: term, list(start_option)) :: Supervisor.on_start()
  def start_link(server, init_arg, opts) when is_atom(server) do
    name = opts[:name] || Registry.supervisor(server)
    opts = Keyword.merge(opts, module: server, init_arg: init_arg)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :module)
    transport = Keyword.fetch!(opts, :transport)
    init_arg = Keyword.fetch!(opts, :init_arg)
    session_mode = Keyword.get(opts, :session_mode, :single)

    {layer, transport_opts} = parse_transport_child(transport, server)

    children = build_children(session_mode, server, layer, transport_opts, init_arg)

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp parse_transport_child(:stdio, server) do
    name = Registry.transport(server, :stdio)
    opts = [name: name, server: Registry.server(server)]
    {STDIO, opts}
  end

  defp parse_transport_child({:streamable_http, opts}, server) do
    name = Registry.transport(server, :streamable_http)
    opts = Keyword.merge(opts, name: name, server: Registry.server(server))
    {StreamableHTTP, opts}
  end

  defp parse_transport_child({:sse, _opts}, _server), do: raise("unimplemented")

  defp build_children(:single, server, layer, transport_opts, init_arg) do
    server_name = Registry.server(server)
    server_transport = [layer: layer, name: transport_opts[:name]]

    server_opts = [
      module: server,
      name: server_name,
      transport: server_transport,
      init_arg: init_arg,
      session_mode: :single
    ]

    [{Base, server_opts}, {layer, transport_opts}]
  end

  defp build_children(:per_client, server, layer, transport_opts, init_arg) do
    server_name = Registry.server(server)
    server_transport = [layer: layer, name: transport_opts[:name]]

    server_opts = [
      module: server,
      name: server_name,
      transport: server_transport,
      init_arg: init_arg,
      session_mode: :per_client
    ]

    [Session.Supervisor, {Base, server_opts}, {layer, transport_opts}]
  end
end
