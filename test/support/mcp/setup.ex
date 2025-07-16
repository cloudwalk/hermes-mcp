defmodule Hermes.MCP.Setup do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 1]
  import ExUnit.Callbacks, only: [start_supervised!: 1, start_supervised!: 2]
  import Hermes.MCP.Assertions

  alias Hermes.MCP.Builders
  alias Hermes.MCP.Message
  alias Hermes.Server.Base
  alias Hermes.Server.Session
  alias Hermes.Server.Transport

  require Message

  def get_request_id(client, method, retries \\ 5) do
    Process.sleep(15 * retries)
    state = :sys.get_state(client)

    request_id =
      Enum.find_value(state.pending_requests, fn {id, request} ->
        if request.method == method, do: id
      end)

    cond do
      request_id != nil -> request_id
      retries > 0 -> get_request_id(client, method, retries - 1)
      true -> nil
    end
  end

  def send_response(client, response) do
    {:ok, encoded} = Message.encode_response(response, response["id"])
    GenServer.cast(client, {:response, encoded})
  end

  def send_error(client, error_response) do
    {:ok, encoded} = Message.encode_error(error_response, error_response["id"])
    GenServer.cast(client, {:response, encoded})
  end

  def send_notification(client, notification) do
    {:ok, encoded} = Message.encode_notification(notification)
    GenServer.cast(client, {:response, encoded})
  end

  def initialize_client(client, opts \\ []) do
    server_capabilities =
      opts[:server_capabilities] ||
        %{
          "resources" => %{},
          "tools" => %{},
          "prompts" => %{}
        }

    GenServer.cast(client, :initialize)
    Process.sleep(50)

    request_id = get_request_id(client, "initialize")
    assert request_id

    response =
      Builders.init_response(
        request_id,
        "2025-03-26",
        %{"name" => "TestServer", "version" => "1.0.0"},
        server_capabilities
      )

    send_response(client, response)

    Process.sleep(50)
  end

  def initialized_client_with_server(ctx) do
    protocol_version = ctx[:protocol_version]
    capabilities = ctx[:client_capabilities]
    info = ctx[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}

    start_supervised!(Hermes.Server.Registry)
    transport = start_supervised!(StubTransport)

    client_opts = [
      transport: [layer: StubTransport, name: transport],
      client_info: info,
      capabilities: capabilities,
      protocol_version: protocol_version
    ]

    client = start_supervised!({Hermes.Client.Base, client_opts})
    unique_id = System.unique_integer([:positive])
    start_supervised!({StubServer, transport: StubTransport}, id: unique_id)
    assert server = Hermes.Server.Registry.whereis_server(StubServer)

    Process.sleep(30)

    StubTransport.set_client(transport, client)

    Process.sleep(80)

    assert_client_initialized(client)
    assert_server_initialized(server)

    :ok = StubTransport.clear(transport)

    Map.merge(ctx, %{transport: transport, client: client, server: server})
  end

  def initialized_server(ctx) do
    session_id = ctx[:session_id] || "test-session-123"
    protocol_version = ctx[:protocol_version]
    capabilities = ctx[:client_capabilities]
    info = ctx[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}

    start_supervised!(Hermes.Server.Registry)
    transport = start_supervised!(StubTransport)

    # Start session supervisor
    start_supervised!({Hermes.Server.Session.Supervisor, server: StubServer, registry: Hermes.Server.Registry})

    server_opts = [
      module: StubServer,
      name: Hermes.Server.Registry.server(StubServer),
      registry: Hermes.Server.Registry,
      transport: [layer: StubTransport, name: transport]
    ]

    server = start_supervised!({Base, server_opts})
    assert server == Hermes.Server.Registry.whereis_server(StubServer)

    request = Builders.init_request(protocol_version, info, capabilities)
    assert {:ok, _} = GenServer.call(server, {:request, request, session_id, %{}})
    notification = Builders.build_notification("notifications/initialized", %{})

    assert :ok =
             GenServer.cast(server, {:notification, notification, session_id, %{}})

    Process.sleep(50)

    assert_server_initialized(server)

    :ok = StubTransport.clear(transport)

    Map.merge(ctx, %{
      transport: transport,
      server: server,
      session_id: session_id,
      server_registry: Hermes.Server.Registry,
      server_module: StubServer
    })
  end

  def initialized_base_server(ctx) do
    server_module = StubServer
    session_id = ctx[:session_id] || "test-session-123"
    protocol_version = ctx[:protocol_version]
    capabilities = ctx[:client_capabilities]
    transport = ctx[:transport] || StubTransport
    info = ctx[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}

    # session supervisor
    %{registry: registry} = ctx = with_default_registry(ctx)

    start_supervised!({Session.Supervisor, server: server_module, registry: ctx.registry})

    assert registry.supervisor(server_module, :session_supervisor)

    # base server
    server_name = registry.server(server_module)
    transport_name = registry.transport(server_module, transport)

    server_opts = [
      module: server_module,
      name: server_name,
      registry: registry,
      transport: [
        layer: transport,
        name: transport_name
      ]
    ]

    start_supervised!({Base, server_opts})
    assert server = registry.whereis_server(server_module)

    # transport
    start_supervised!({transport, name: transport_name, server: server_name, registry: registry})

    assert registry.whereis_transport(server_module, transport)

    request = Builders.init_request(protocol_version, info, capabilities)
    assert {:ok, _} = GenServer.call(server, {:request, request, session_id})
    notification = Builders.build_notification("notifications/initialized", %{})
    assert :ok = GenServer.cast(server, {:notification, notification, session_id})

    Process.sleep(50)

    assert_server_initialized(server)

    :ok = StubTransport.clear(transport)

    Map.merge(ctx, %{transport: transport, server: server, session_id: session_id})
  end

  def server_with_stdio_transport(ctx) do
    name = ctx[:name] || :test_stdio_server
    name = Hermes.Server.Registry.server(name)
    server_module = ctx[:server_module] || StubServer

    transport_name = Hermes.Server.Registry.transport(server_module, :stdio)
    start_supervised!({Transport.STDIO, name: transport_name, server: server_module})

    assert transport =
             Hermes.Server.Registry.whereis_transport(server_module, :stdio)

    opts = [
      module: server_module,
      name: name,
      transport: [layer: Transport.STDIO, name: transport_name]
    ]

    start_supervised!({Base, opts})
    assert server = Hermes.Server.Registry.whereis_server(server_module)

    Map.merge(ctx, %{server: server, transport: transport})
  end

  def with_default_registry(ctx) do
    start_supervised!(Hermes.Server.Registry)
    assert Process.whereis(Hermes.Server.Registry)
    Map.put(ctx, :registry, Hermes.Server.Registry)
  end

  def initialized_client(context) do
    import Mox

    start_supervised!(Hermes.Server.Registry)

    server_capabilities =
      context[:server_capabilities] ||
        %{
          "resources" => %{},
          "tools" => %{},
          "prompts" => %{}
        }

    client_info =
      context[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}

    client_capabilities = context[:client_capabilities] || %{}

    client =
      start_supervised!(
        {Hermes.Client.Base,
         transport: [layer: Hermes.MockTransport, name: MockTransport],
         client_info: client_info,
         capabilities: client_capabilities},
        restart: :temporary
      )

    allow(Hermes.MockTransport, self(), fn -> client end)
    initialize_client(client, server_capabilities: server_capabilities)

    Map.put(context, :client, client)
  end
end
