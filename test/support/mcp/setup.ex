defmodule Hermes.MCP.Setup do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 1]
  import ExUnit.Callbacks, only: [start_supervised!: 1, start_supervised!: 2]
  import Hermes.MCP.Assertions

  alias Hermes.MCP.Builders
  alias Hermes.MCP.Message
  alias Hermes.Server.Transport

  require Message

  def initialized_client(ctx) do
    protocol_version = ctx[:protocol_version]
    capabilities = ctx[:client_capabilities]
    info = ctx[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}

    transport = start_supervised!(StubTransport)

    client_opts = [
      transport: [layer: StubTransport, name: transport],
      client_info: info,
      capabilities: capabilities,
      protocol_version: protocol_version
    ]

    client = start_supervised!({Hermes.Client, client_opts})
    unique_id = System.unique_integer([:positive])
    start_supervised!({StubServer, transport: StubTransport}, id: unique_id)
    assert server = Hermes.Server.Registry.whereis_server(StubServer)

    Process.sleep(30)

    StubTransport.set_client(transport, client)

    Process.sleep(50)

    assert_client_initialized client
    assert_server_initialized server

    :ok = StubTransport.clear(transport)

    Map.merge(ctx, %{transport: transport, client: client, server: server})
  end

  def initialized_server(ctx) do
    session_id = ctx[:session_id] || "test-session-123"
    protocol_version = ctx[:protocol_version]
    capabilities = ctx[:client_capabilities]
    info = ctx[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}

    transport = start_supervised!(StubTransport)
    start_supervised!({StubServer, transport: StubTransport})
    assert server = Hermes.Server.Registry.whereis_server(StubServer)

    request = Builders.init_request(protocol_version, info, capabilities)
    assert {:ok, _} = GenServer.call(server, {:request, request, session_id})
    notification = Builders.build_notification("notifications/initialized", %{})
    assert :ok = GenServer.cast(server, {:notification, notification, session_id})

    Process.sleep(50)

    assert_server_initialized server

    :ok = StubTransport.clear(transport)

    Map.merge(ctx, %{transport: transport, server: server, session_id: session_id})
  end

  def server_with_stdio_transport(ctx) do
    name = ctx[:name] || :test_stdio_server
    name = Hermes.Server.Registry.server(name)
    server_module = ctx[:server_module] || StubServer

    transport_name = Hermes.Server.Registry.transport(server_module, :stdio)
    start_supervised!({Transport.STDIO, name: transport_name, server: server_module})
    assert transport = Hermes.Server.Registry.whereis_transport(server_module, :stdio)

    opts = [
      module: server_module,
      init_arg: :ok,
      name: name,
      transport: [layer: Transport.STDIO, name: transport_name]
    ]

    start_supervised!({Hermes.Server.Base, opts})
    assert server = Hermes.Server.Registry.whereis_server(server_module)

    Map.merge(ctx, %{server: server, transport: transport})
  end

  def server_with_streamable_http_transport(ctx) do
    name = ctx[:name] || :test_stdio_server
    name = Hermes.Server.Registry.server(name)
    server_module = ctx[:server_module] || StubServer

    transport_name = Hermes.Server.Registry.transport(server_module, :streamable_http)
    start_supervised!({Transport.StreamableHTTP, name: transport_name, server: server_module})
    assert transport = Hermes.Server.Registry.whereis_server(server_module)

    opts = [
      module: server_module,
      init_arg: :ok,
      name: name,
      transport: [layer: Transport.StreamableHTTP, name: transport_name]
    ]

    start_supervised!({Hermes.Server.Base, opts})
    assert server = Hermes.Server.Registry.whereis_server(StubServer)

    Map.merge(ctx, %{server: server, transport: transport})
  end
end
