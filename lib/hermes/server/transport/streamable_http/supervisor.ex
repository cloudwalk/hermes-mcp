defmodule Hermes.Server.Transport.StreamableHTTP.Supervisor do
  @moduledoc """
  Supervisor for the StreamableHTTP transport system.

  This supervisor manages both the transport process and the session registry
  using a `one_for_all` strategy to ensure proper coordination between them.

  ## Children

  1. `SessionRegistry` - Manages active sessions in ETS
  2. `StreamableHTTP` - The main transport process

  ## Restart Strategy

  Uses `one_for_all` strategy because:
  - If the session registry crashes, the transport cannot function properly
  - If the transport crashes, existing sessions become invalid
  - Both components need to restart together to maintain consistency

  ## Name Registration

  Both child processes MUST be registered with names for easy access:
  - `:transport_name` - Required name for the transport process
  - `:registry_name` - Required name for the session registry

  ## Usage

      # Start the supervisor with required names
      opts = [
        server: my_server_process,
        transport_name: :my_transport,
        registry_name: :my_session_registry
      ]

      {:ok, supervisor_pid} = Hermes.Server.Transport.StreamableHTTP.Supervisor.start_link(opts)

      # Access processes by name
      GenServer.call(:my_transport, :create_session)
      SessionRegistry.lookup_session(:my_session_registry, session_id)

  ## Integration with Base Server

      server_opts = [
        module: MyServer,
        name: :my_server,
        transport: [
          layer: Hermes.Server.Transport.StreamableHTTP.Supervisor,
          name: :my_transport_supervisor,
          server: :my_server,
          transport_name: :my_transport,
          registry_name: :my_session_registry
        ]
      ]

      {:ok, server} = Hermes.Server.Base.start_link(server_opts)
  """

  use Supervisor

  import Peri

  alias Hermes.Logging
  alias Hermes.Server.Transport.StreamableHTTP
  alias Hermes.Server.Transport.StreamableHTTP.SessionRegistry
  alias Hermes.Telemetry

  @type option ::
          {:server, GenServer.server()}
          | {:transport_name, GenServer.name()}
          | {:registry_name, GenServer.name()}
          | {:table_name, atom()}
          | {:name, GenServer.name()}

  defschema(:parse_options, [
    {:server, {:required, {:oneof, [{:custom, &Hermes.genserver_name/1}, :pid, {:tuple, [:atom, :any]}]}}},
    {:transport_name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:registry_name, {:required, {:custom, &Hermes.genserver_name/1}}},
    {:table_name, {:atom, {:default, :hermes_streamable_http_sessions}}},
    {:name, {:custom, &Hermes.genserver_name/1}}
  ])

  @doc """
  Starts the StreamableHTTP transport supervisor.

  ## Parameters
    * `opts` - Configuration options
      * `:server` - (required) The MCP server process
      * `:transport_name` - (required) Name for the transport process
      * `:registry_name` - (required) Name for the session registry
      * `:name` - Optional name for the supervisor

  ## Examples

      iex> opts = [
      ...>   server: my_server,
      ...>   transport_name: :my_transport,
      ...>   registry_name: :my_registry
      ...> ]
      iex> Hermes.Server.Transport.StreamableHTTP.Supervisor.start_link(opts)
      {:ok, pid}
  """
  @spec start_link(Enumerable.t(option())) :: Supervisor.on_start()
  def start_link(opts) do
    opts = parse_options!(opts)
    supervisor_name = Keyword.get(opts, :name)

    if supervisor_name do
      Supervisor.start_link(__MODULE__, Map.new(opts), name: supervisor_name)
    else
      Supervisor.start_link(__MODULE__, Map.new(opts))
    end
  end

  # Supervisor callbacks

  @impl Supervisor
  def init(%{server: server, transport_name: transport_name, registry_name: registry_name, table_name: table_name}) do
    Logging.transport_event("supervisor_starting", %{
      server: server,
      transport_name: transport_name,
      registry_name: registry_name
    })

    Telemetry.execute(
      Telemetry.event_transport_init(),
      %{system_time: System.system_time()},
      %{transport: :streamable_http_supervisor, server: server}
    )

    children = [
      {SessionRegistry, name: registry_name, table_name: table_name},
      {StreamableHTTP, server: server, name: transport_name, registry: registry_name}
    ]

    Supervisor.init(children, strategy: :one_for_all, name: __MODULE__)
  end
end
