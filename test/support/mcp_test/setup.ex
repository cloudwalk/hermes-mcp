defmodule MCPTest.Setup do
  @moduledoc """
  Composable setup functions for MCP testing.

  Provides functions that can be chained together to set up test environments
  for both client and server testing with various configurations.

  ## Usage

      # In test setup
      setup do
        %{}
        |> initialize_client()
      end
      
      # Or in individual tests
      test "my test" do
        ctx = %{}
        |> initialize_server()
        
        # Use ctx.server...
      end
  """

  import ExUnit.Callbacks, only: [start_supervised!: 1, start_supervised!: 2]
  import MCPTest.Builders

  alias Hermes.MCP.Message

  @doc """
  Sets up a client process with default configuration.

  ## Options

  - `:client_info` - Custom client info map
  - `:capabilities` - Custom client capabilities
  - `:name` - Process name for the client
  - `:transport` - Transport configuration

  ## Examples

      setup_client(%{})
      setup_client(%{}, client_info: %{"name" => "MyClient"})
  """
  def setup_client(ctx, opts \\ []) do
    transport =
      case opts[:transport] || ctx[:transport] do
        nil ->
          transport_name = :mock_client_transport
          start_supervised!({MCPTest.MockTransport, [name: transport_name]})
          [layer: MCPTest.MockTransport, name: transport_name]

        existing ->
          existing
      end

    client_opts = build_client_opts(ctx, Keyword.put(opts, :transport, transport))
    client = start_supervised!({Hermes.Client, client_opts}, restart: :temporary)

    Map.put(ctx, :client, client)
  end

  @doc """
  Initializes a client by performing the MCP handshake.

  Sends the initialize request and processes the response,
  then sends the initialized notification.

  ## Options

  - `:server_capabilities` - Custom server capabilities to respond with
  - `:server_info` - Custom server info to respond with
  - `:timeout` - Timeout for the initialization process
  """
  def initialize_client(ctx, opts \\ []) do
    client = ctx.client

    MCPTest.Helpers.send_initialize_request(client)

    request_id = MCPTest.Helpers.get_request_id(client, "initialize")

    merged_opts =
      Keyword.merge(
        Enum.to_list(Map.take(ctx, [:server_capabilities, :server_info])),
        opts
      )

    response = init_response(request_id, merged_opts)
    MCPTest.Helpers.send_response(client, response)

    notification = initialized_notification()
    MCPTest.Helpers.send_notification(client, notification)

    ctx
  end

  @doc """
  Sets up a server process with default configuration.

  ## Options

  - `:module` - Server implementation module (defaults to TestServer)
  - `:name` - Process name for the server
  - `:transport` - Transport configuration
  """
  def setup_server(ctx, opts \\ []) do
    server_opts = build_server_opts(ctx, opts)
    server = start_supervised!({Hermes.Server.Base, server_opts})

    Map.put(ctx, :server, server)
  end

  @doc """
  Initializes a server by performing the MCP handshake.

  Sends an initialize request to the server and processes
  the response, then sends the initialized notification.
  """
  def initialize_server(ctx, opts \\ []) do
    server = ctx.server

    init_request = init_request(opts)
    {:ok, encoded} = Message.encode_request(init_request, 1)
    {:ok, _response} = GenServer.call(server, {:message, encoded})

    notification = initialized_notification()
    {:ok, encoded_notification} = Message.encode_notification(notification)
    {:ok, nil} = GenServer.call(server, {:message, encoded_notification})

    ctx
  end

  defp build_client_opts(_ctx, opts) do
    transport = opts[:transport] || raise "Transport must be provided in opts"
    client_info = opts[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}
    capabilities = opts[:capabilities]
    name = opts[:name] || :test_client

    base_opts = [
      transport: transport,
      client_info: client_info,
      name: name
    ]

    if capabilities do
      Keyword.put(base_opts, :capabilities, capabilities)
    else
      base_opts
    end
  end

  defp build_server_opts(ctx, opts) do
    default_transport =
      case opts[:transport] || ctx[:transport] do
        nil ->
          transport_name = :mock_server_transport
          start_supervised!({MCPTest.MockTransport, [name: transport_name]})
          [layer: MCPTest.MockTransport, name: transport_name]

        existing_transport ->
          existing_transport
      end

    transport = default_transport
    module = opts[:module] || TestServer
    name = opts[:name] || :test_server

    [
      module: module,
      name: name,
      transport: transport
    ]
  end

  @doc """
  Complete client setup with initialization.

  This is the most common setup pattern - creates a client
  with mock transport and performs MCP initialization.
  """
  def initialized_client(ctx \\ %{}, opts \\ []) do
    ctx
    |> setup_client(opts)
    |> initialize_client(opts)
  end

  @doc """
  Sets up a server with mock transport without initialization.

  Use this when you need a server but want to control initialization manually.
  """
  def server_with_mock_transport(ctx \\ %{}, opts \\ []) do
    setup_server(ctx, opts)
  end

  @doc """
  Complete server setup with initialization.

  Creates a server with mock transport and performs MCP initialization.
  """
  def initialized_server(ctx \\ %{}, opts \\ []) do
    ctx
    |> setup_server(opts)
    |> initialize_server(opts)
  end

  @doc """
  Sets up both client and server for integration testing.

  Note: This sets up separate mock transports for each.
  For true integration testing, you'd want a real transport.
  """
  def client_and_server(ctx \\ %{}, opts \\ []) do
    client_opts = opts[:client] || []
    server_opts = opts[:server] || []

    ctx
    |> initialize_client(client_opts)
    |> initialize_server(server_opts)
  end

  @doc """
  Adds custom capabilities to the test context.

  This is useful for setting up specific capability configurations
  that will be used during client/server initialization.
  """
  def with_capabilities(ctx, client_capabilities \\ nil, server_capabilities \\ nil) do
    ctx = if client_capabilities, do: Map.put(ctx, :client_capabilities, client_capabilities), else: ctx
    ctx = if server_capabilities, do: Map.put(ctx, :server_capabilities, server_capabilities), else: ctx
    ctx
  end

  @doc """
  Adds custom client/server info to the test context.
  """
  def with_info(ctx, client_info \\ nil, server_info \\ nil) do
    ctx = if client_info, do: Map.put(ctx, :client_info, client_info), else: ctx
    ctx = if server_info, do: Map.put(ctx, :server_info, server_info), else: ctx
    ctx
  end
end
