defmodule Hermes.Server.Supervisor do
  @moduledoc false

  use Supervisor, restart: :permanent

  alias Hermes.Server.Base
  alias Hermes.Server.Registry
  alias Hermes.Server.Session
  alias Hermes.Server.Transport.STDIO
  alias Hermes.Server.Transport.StreamableHTTP

  # TODO(zoedsoupe): need to implement backward compatibility with SSE/2024-05-11
  @type sse :: {:sse, keyword()}
  @type stream_http :: {:streamable_http, keyword()}

  @type transport :: :stdio | stream_http | sse

  @type start_option :: {:transport, transport} | {:name, Supervisor.name()}

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
    {layer, transport_opts} = parse_transport_child(transport, server)

    server_name = Registry.server(server)
    server_transport = [layer: layer, name: transport_opts[:name]]

    server_opts = [
      module: server,
      name: server_name,
      transport: server_transport,
      init_arg: init_arg,
      session_mode: :per_client
    ]

    children =
      if layer == StreamableHTTP,
        do: [{Session.Supervisor, server}, {Base, server_opts}, {layer, transport_opts}],
        else: [{Base, server_opts}, {layer, transport_opts}]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp parse_transport_child(:stdio, server) do
    name = Registry.transport(server, :stdio)
    opts = [name: name, server: server]
    {STDIO, opts}
  end

  defp parse_transport_child({:streamable_http, opts}, server) do
    name = Registry.transport(server, :streamable_http)
    opts = Keyword.merge(opts, name: name, server: server)
    {StreamableHTTP, opts}
  end

  defp parse_transport_child({:sse, _opts}, _server), do: raise("unimplemented")
end
