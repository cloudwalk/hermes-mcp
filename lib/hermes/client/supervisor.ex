defmodule Hermes.Client.Supervisor do
  @moduledoc false

  use Supervisor

  alias Hermes.Client.Base
  alias Hermes.Transport.SSE
  alias Hermes.Transport.STDIO
  alias Hermes.Transport.StreamableHTTP
  alias Hermes.Transport.Websocket

  @type transport_config ::
          {:stdio, keyword()}
          | {:sse, keyword()}
          | {:websocket, keyword()}
          | {:streamable_http, keyword()}

  @doc """
  Starts the client supervisor.

  ## Arguments

    * `client_module` - The client module using `Hermes.Client`
    * `opts` - Supervisor options including:
      * `:name` - Optional custom name for the client process
      * `:transport` - Transport configuration (required)
      * `:transport_name` - Optional custom name for the transport process
      * `:client_info` - Client identification info
      * `:capabilities` - Client capabilities map
      * `:protocol_version` - MCP protocol version

  ## Examples

      # Simple usage with module names
      Hermes.Client.Supervisor.start_link(MyApp.MCPClient, 
        transport: {:stdio, command: "mcp", args: ["server"]},
        client_info: %{"name" => "MyApp", "version" => "1.0.0"},
        capabilities: %{"roots" => %{}},
        protocol_version: "2024-11-05"
      )
      
      # With custom names (e.g., for distributed systems)
      Hermes.Client.Supervisor.start_link(MyApp.MCPClient,
        name: {:via, Horde.Registry, {MyCluster, "client_1"}},
        transport_name: {:via, Horde.Registry, {MyCluster, "transport_1"}},
        transport: {:stdio, command: "mcp", args: ["server"]},
        client_info: %{"name" => "MyApp", "version" => "1.0.0"},
        capabilities: %{"roots" => %{}},
        protocol_version: "2024-11-05"
      )
  """
  @spec start_link(module(), keyword()) :: Supervisor.on_start()
  def start_link(client_module, opts) do
    opts = Keyword.put(opts, :client_module, client_module)

    if name = Keyword.get(opts, :name) do
      Supervisor.start_link(__MODULE__, opts, name: name)
    else
      Supervisor.start_link(__MODULE__, opts)
    end
  end

  @impl true
  def init(opts) do
    client_module = Keyword.fetch!(opts, :client_module)
    transport = Keyword.fetch!(opts, :transport)

    client_info = Keyword.fetch!(opts, :client_info)
    capabilities = Keyword.fetch!(opts, :capabilities)
    protocol_version = Keyword.fetch!(opts, :protocol_version)

    client_name = opts[:client_name] || client_module
    transport_name = derive_transport_name(opts[:transport_name], client_name)

    {layer, transport_opts} = parse_transport_config(transport)

    client_transport = [layer: layer, name: transport_name]

    client_opts = [
      transport: client_transport,
      client_info: client_info,
      capabilities: capabilities,
      protocol_version: protocol_version,
      name: client_name
    ]

    children = [
      {Base, client_opts},
      {layer, transport_opts ++ [name: transport_name, client: client_name]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp derive_transport_name(transport, _client) when not is_nil(transport), do: transport

  defp derive_transport_name(nil, client) when is_atom(client) do
    Module.concat(client, "Transport")
  end

  defp derive_transport_name(_transport, _client) do
    raise ArgumentError, """
    When using a non-atom client name (e.g., via tuple), you must provide an explicit :transport_name option.

    Example:
      name: {:via, Registry, {MyRegistry, "client"}},
      transport_name: {:via, Registry, {MyRegistry, "transport"}}
    """
  end

  defp parse_transport_config({:stdio, opts}), do: {STDIO, opts}
  defp parse_transport_config({:streamable_http, opts}), do: {StreamableHTTP, opts}

  defp parse_transport_config({:sse, opts}) do
    IO.warn(
      "The :sse transport option is deprecated as of MCP specification 2025-03-26. " <>
        "Please use {:streamable_http, opts} instead. " <>
        "The SSE transport is maintained only for backward compatibility with MCP protocol version 2024-11-05.",
      []
    )

    {SSE, opts}
  end

  defp parse_transport_config({:websocket, opts}), do: {Websocket, opts}
end
