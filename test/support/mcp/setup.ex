defmodule Hermes.MCP.Setup do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 1]
  import ExUnit.Callbacks, only: [start_supervised!: 1]
  import Hermes.MCP.Assertions

  alias Hermes.MCP.Builders
  alias Hermes.MCP.Message

  require Hermes.MCP.Message

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
    StubTransport.set_client(transport, client)

    GenServer.cast(client, :initialize)
    Process.sleep(50)

    assert StubTransport.count(transport) == 1
    assert [%{"id" => id} = init_message] = StubTransport.get_messages(transport)
    assert Message.is_initialize(init_message)

    response = Builders.init_response(id, protocol_version, %{"name" => "TestServer", "version" => "1.0.0"})
    assert {:ok, data} = Builders.encode_message(response)
    assert is_binary(data)

    GenServer.cast(client, {:response, data})
    Process.sleep(50)

    assert StubTransport.count(transport) == 2
    assert [_init, notification] = StubTransport.get_messages(transport)
    assert Message.is_initialize_lifecycle(notification)

    assert_client_initialized client

    Map.merge(ctx, %{transport: transport, client: client})
  end
end
