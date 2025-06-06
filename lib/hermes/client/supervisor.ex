defmodule Hermes.Client.Supervisor do
  @moduledoc """
  Supervisor for MCP client processes.

  This supervisor manages the lifecycle of an MCP client, including:
  - The transport layer (STDIO, SSE, WebSocket, or StreamableHTTP)
  - The Base client process that handles MCP protocol

  The supervision strategy is `:rest_for_one`, meaning if the transport
  crashes, both transport and client are restarted, but if only the client
  crashes, only the client is restarted.

  ## Supervision Tree

  ```
  Supervisor
  ├── Transport (STDIO, SSE, WebSocket, or StreamableHTTP)
  └── Base Client
  ```
  """

  use Supervisor, restart: :permanent

  alias Hermes.Client.Base
  alias Hermes.Client.Registry
  alias Hermes.Transport.SSE
  alias Hermes.Transport.STDIO
  alias Hermes.Transport.StreamableHTTP
  alias Hermes.Transport.WebSocket

  @type transport ::
          :stdio
          | {:stdio, keyword()}
          | {:sse, keyword()}
          | {:websocket, keyword()}
          | {:streamable_http, keyword()}

  @type start_option ::
          {:transport, transport}
          | {:name, Supervisor.name()}
          | {:client_info, map()}
          | {:capabilities, map()}
          | {:protocol_version, String.t()}

  @doc """
  Starts the client supervisor.

  ## Parameters

    * `client_module` - The module implementing `Hermes.Client.Behaviour`
    * `init_arg` - Argument passed to the client's callbacks
    * `opts` - Options including:
      * `:transport` - Transport configuration (required)
      * `:name` - Supervisor name (optional)
      * `:client_info` - Client metadata (optional, uses module callbacks)
      * `:capabilities` - Client capabilities (optional, uses module callbacks)  
      * `:protocol_version` - Protocol version (optional, uses module callbacks)

  ## Examples

      # Start with STDIO transport
      Hermes.Client.Supervisor.start_link(MyClient, [], transport: :stdio)

      # Start with SSE transport
      Hermes.Client.Supervisor.start_link(MyClient, [],
        transport: {:sse, base_url: "http://localhost:8000/mcp"}
      )
  """
  @spec start_link(client_module :: module, init_arg :: term, list(start_option)) :: Supervisor.on_start()
  def start_link(client_module, init_arg, opts) when is_atom(client_module) do
    name = opts[:name] || Registry.supervisor(client_module)
    opts = Keyword.merge(opts, module: client_module, init_arg: init_arg)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    client_module = Keyword.fetch!(opts, :module)
    transport = Keyword.fetch!(opts, :transport)
    init_arg = Keyword.fetch!(opts, :init_arg)

    state = %{module: client_module, init_arg: init_arg}
    client_info = opts[:client_info] || client_module.client_info(state)
    capabilities = opts[:capabilities] || client_module.client_capabilities(state)
    protocol_version = opts[:protocol_version] || client_module.protocol_version(state)

    {transport_layer, transport_opts} = parse_transport_config(transport, client_module)

    client_name = Registry.client(client_module)
    transport_name = transport_opts[:name]

    client_opts = [
      name: client_name,
      transport: [layer: transport_layer, name: transport_name],
      client_info: client_info,
      capabilities: capabilities,
      protocol_version: protocol_version
    ]

    transport_opts = Keyword.put(transport_opts, :client, client_name)

    children = [
      {transport_layer, transport_opts},
      {Base, client_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp parse_transport_config(:stdio, client_module) do
    name = Registry.transport(client_module, :stdio)
    opts = [name: name]
    {STDIO, opts}
  end

  defp parse_transport_config({:stdio, opts}, client_module) do
    name = opts[:name] || Registry.transport(client_module, :stdio)
    opts = Keyword.put(opts, :name, name)
    {STDIO, opts}
  end

  defp parse_transport_config({:sse, opts}, client_module) do
    name = opts[:name] || Registry.transport(client_module, :sse)
    opts = Keyword.put(opts, :name, name)
    {SSE, opts}
  end

  defp parse_transport_config({:websocket, opts}, client_module) do
    name = opts[:name] || Registry.transport(client_module, :websocket)
    opts = Keyword.put(opts, :name, name)
    {WebSocket, opts}
  end

  defp parse_transport_config({:streamable_http, opts}, client_module) do
    name = opts[:name] || Registry.transport(client_module, :streamable_http)
    opts = Keyword.put(opts, :name, name)
    {StreamableHTTP, opts}
  end
end
