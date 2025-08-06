defmodule StubTransport do
  @moduledoc """
  Simple mock transport for MCP protocol testing.
  Records all messages sent through it for inspection in tests.
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  alias Hermes.MCP.Builders
  alias Hermes.MCP.ID
  alias Hermes.MCP.Message

  require Message

  @type state :: %{
          messages: [String.t()],
          client: GenServer.name() | nil,
          session_id: String.t(),
          test_pid: pid() | nil
        }

  @doc """
  Starts the mock transport.

  ## Options
  - `:name` - Process name (defaults to __MODULE__)
  """
  @impl true
  def start_link(opts \\ []) do
    state = %{messages: [], client: nil, server: nil, test_pid: nil}

    if name = opts[:name] do
      GenServer.start_link(__MODULE__, state, name: name)
    else
      GenServer.start_link(__MODULE__, state)
    end
  end

  @doc """
  Gets all messages sent through this transport.
  """
  def get_messages(transport \\ __MODULE__) do
    GenServer.call(transport, :get_messages)
  end

  def get_last_message(transport \\ __MODULE__) do
    GenServer.call(transport, :get_last_message)
  end

  def set_client(transport \\ __MODULE__, client) do
    GenServer.call(transport, {:set_client, client})
  end

  @doc """
  Sets the test process to receive message notifications.
  """
  def set_test_pid(transport \\ __MODULE__, test_pid) do
    GenServer.call(transport, {:set_test_pid, test_pid})
  end

  @doc """
  Clears all recorded messages.
  """
  def clear(transport \\ __MODULE__) do
    GenServer.call(transport, :clear)
  end

  @doc """
  Gets the count of messages sent.
  """
  def count(transport \\ __MODULE__) do
    GenServer.call(transport, :count)
  end

  def send_to_client(transport \\ __MODULE__, response) when is_map(response) do
    {:ok, response} = Builders.encode_message(response)
    GenServer.call(transport, {:send_to_client, response})
  end

  @impl true
  def send_message(transport \\ __MODULE__, message, _opts \\ []) do
    GenServer.call(transport, {:send_message, message})
  end

  @impl true
  def shutdown(transport \\ __MODULE__) do
    GenServer.call(transport, :shutdown)
  end

  @impl true
  def supported_protocol_versions, do: :all

  @impl true
  def init(state) do
    {:ok, Map.put(state, :session_id, ID.generate_session_id())}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, state.messages |> Enum.reverse() |> Enum.map(&decode_message/1), state}
  end

  def handle_call(:get_last_message, _from, %{messages: messages} = state) do
    last = List.first(messages)
    {:reply, if(last, do: decode_message(last)), state}
  end

  def handle_call(:clear, _from, state) do
    {:reply, :ok, %{state | messages: []}}
  end

  def handle_call({:set_client, client}, _from, state) do
    GenServer.cast(client, :initialize)
    {:reply, :ok, %{state | client: client}}
  end

  def handle_call({:set_test_pid, test_pid}, _from, state) do
    {:reply, :ok, %{state | test_pid: test_pid}}
  end

  def handle_call(:count, _from, state) do
    {:reply, length(state.messages), state}
  end

  def handle_call({:send_message, message}, _from, state) do
    new_messages = [message | state.messages]

    # Send to test process if configured
    if state.test_pid do
      send(state.test_pid, {:send_message, message})
    end

    if is_binary(message) do
      message = decode_message(message)
      forward_to_server(message, state)
    else
      forward_to_server(message, state)
    end

    {:reply, :ok, %{state | messages: new_messages}}
  end

  def handle_call(:shutdown, _from, state) do
    {:stop, :normal, :ok, state}
  end

  def handle_call({:send_to_client, response}, _from, %{client: client} = state) do
    GenServer.cast(client, {:response, response})
    {:reply, :ok, state}
  end

  defp decode_message(message) when is_binary(message) do
    %{} = message = Builders.decode_message(message)
    message
  end

  defp forward_to_server(message, state) when Message.is_request(message) do
    if message["method"] == "sampling/createMessage" do
      :ok
    else
      name = Hermes.Server.Registry.server(StubServer)

      {:ok, response} =
        GenServer.call(name, {:request, message, state.session_id, %{}})

      GenServer.cast(state.client, {:response, response})
    end
  end

  defp forward_to_server(message, state) when Message.is_response(message) or Message.is_error(message) do
    name = Hermes.Server.Registry.server(StubServer)
    GenServer.cast(name, {:response, message, state.session_id, %{}})
  end

  defp forward_to_server(message, state) when Message.is_notification(message) do
    name = Hermes.Server.Registry.server(StubServer)
    :ok = GenServer.cast(name, {:notification, message, state.session_id})
  end
end
