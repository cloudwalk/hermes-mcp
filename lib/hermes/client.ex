defmodule Hermes.Client do
  @moduledoc """
  Build MCP clients with ease.

  ## Usage

      defmodule MyApp.MCPClient do
        use Hermes.Client,
          name: "My App",
          version: "1.0.0",
          capabilities: [:roots, :sampling],
          transport: {:stdio, command: "mcp", args: ["run", "server.py"]}

        # Or define start_link to allow runtime transport configuration
        def start_link(opts) do
          Hermes.Client.start_link(__MODULE__, [], 
            transport: opts[:transport] || {:stdio, command: "mcp", args: ["run", "server.py"]}
          )
        end
      end

  ## Transport Options

  - `{:stdio, opts}` - STDIO transport
    - `:command` - Command to execute
    - `:args` - Command arguments
    - `:env` - Environment variables
  - `{:sse, opts}` - Server-Sent Events
    - `:base_url` - Server URL
    - `:headers` - HTTP headers
  - `{:websocket, opts}` - WebSocket transport
    - `:url` - WebSocket URL
    - `:headers` - Connection headers
  - `{:streamable_http, opts}` - Streamable HTTP
    - `:base_url` - Server URL
    - `:headers` - HTTP headers

  ## Client Capabilities

  Capabilities define what features your client supports:

  - `:roots` - Filesystem roots support
  - `{:roots, list_changed: true}` - With change notifications
  - `:sampling` - LLM sampling support

  ## Quick Connect

  For one-off connections:

      {:ok, client} = Hermes.Client.connect(:stdio, "mcp run server.py")
      Hermes.Client.Base.ping(client)
  """

  alias Hermes.Client.ConfigurationError

  @client_capabilities ~w(roots sampling)a
  @default_protocol_version "2025-03-26"

  @doc """
  Starts a client with its supervision tree.

  ## Examples

      # Start with default options
      Hermes.Client.start_link(MyClient, [], [])
      
      # Start with custom name and transport override
      Hermes.Client.start_link(MyClient, [], 
        name: {:local, :my_client},
        transport: {:stdio, command: "different-server"}
      )
  """
  defdelegate start_link(mod, init_arg, opts), to: Hermes.Client.Supervisor

  @doc """
  Connects to an MCP server with minimal configuration.

  This is useful for one-off connections or testing.

  ## Examples

      # STDIO transport
      {:ok, client} = Hermes.Client.connect(:stdio, "mcp run server.py")

      # SSE transport
      {:ok, client} = Hermes.Client.connect(:sse, "http://localhost:8000/mcp")

      # WebSocket transport
      {:ok, client} = Hermes.Client.connect(:websocket, "ws://localhost:8000/ws")
  """
  def connect(transport_type, command_or_url, opts \\ []) do
    client_info = opts[:client_info] || %{"name" => "Hermes Client", "version" => "0.1.0"}
    capabilities = opts[:capabilities] || @default_capabilities
    protocol_version = opts[:protocol_version] || @default_protocol_version

    transport_config = parse_transport_shorthand(transport_type, command_or_url, opts)

    supervisor_opts = [
      transport: transport_config,
      client_info: client_info,
      capabilities: capabilities,
      protocol_version: protocol_version
    ]

    case Hermes.Client.Supervisor.start_link(__MODULE__.OneOffClient, [], supervisor_opts) do
      {:ok, supervisor} ->
        # Get the actual client pid from the supervisor
        client = Hermes.Client.Supervisor.client_pid(supervisor)
        {:ok, client}

      error ->
        error
    end
  end

  defmodule OneOffClient do
    @moduledoc false
    @behaviour Hermes.Client.Behaviour

    def client_info(state), do: state.client_info
    def client_capabilities(state), do: state.capabilities
    def protocol_version(state), do: state.protocol_version
  end

  @doc false
  defmacro __using__(opts) do
    module = __CALLER__.module

    name = opts[:name]
    version = opts[:version]
    transport = opts[:transport]
    capabilities = Enum.reduce(opts[:capabilities] || [], %{}, &parse_capability/2)
    protocol_version = opts[:protocol_version] || @default_protocol_version

    if is_nil(name) and is_nil(version) do
      raise ConfigurationError, module: module, missing_key: :both
    end

    if is_nil(name), do: raise(ConfigurationError, module: module, missing_key: :name)
    if is_nil(version), do: raise(ConfigurationError, module: module, missing_key: :version)

    quote do
      @behaviour Hermes.Client.Behaviour

      import Hermes.Client.Base

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor,
          restart: :permanent
        }
      end

      @impl Hermes.Client.Behaviour
      def client_info(_state) do
        %{"name" => unquote(name), "version" => unquote(version)}
      end

      @impl Hermes.Client.Behaviour
      def client_capabilities(_state) do
        unquote(Macro.escape(capabilities))
      end

      @impl Hermes.Client.Behaviour
      def protocol_version(_state) do
        unquote(protocol_version)
      end

      defoverridable client_info: 1, client_capabilities: 1, protocol_version: 1, child_spec: 1, start_link: 1
    end
  end

  @doc """
  Guard to check if a capability is valid.
  """
  defguard is_client_capability(capability) when capability in @client_capabilities

  defp parse_capability(capability, capabilities) when is_client_capability(capability) do
    Map.put(capabilities, to_string(capability), %{})
  end

  defp parse_capability({:roots, opts}, capabilities) do
    list_changed? = opts[:list_changed] || opts[:listChanged]

    capabilities
    |> Map.put("roots", %{})
    |> then(&if list_changed?, do: put_in(&1, ["roots", "listChanged"], true), else: &1)
  end

  defp parse_capability({capability, _opts}, capabilities) when is_client_capability(capability) do
    Map.put(capabilities, to_string(capability), %{})
  end

  defp parse_transport_shorthand(:stdio, command, opts) when is_binary(command) do
    [cmd | args] = String.split(command, " ")
    stdio_opts = Keyword.merge(opts[:transport_opts] || [], command: cmd, args: args)
    {:stdio, stdio_opts}
  end

  defp parse_transport_shorthand(:sse, url, opts) when is_binary(url) do
    sse_opts = Keyword.put(opts[:transport_opts] || [], :base_url, url)
    {:sse, sse_opts}
  end

  defp parse_transport_shorthand(:websocket, url, opts) when is_binary(url) do
    ws_opts = Keyword.put(opts[:transport_opts] || [], :url, url)
    {:websocket, ws_opts}
  end

  defp parse_transport_shorthand(:streamable_http, url, opts) when is_binary(url) do
    http_opts = Keyword.put(opts[:transport_opts] || [], :base_url, url)
    {:streamable_http, http_opts}
  end
end
