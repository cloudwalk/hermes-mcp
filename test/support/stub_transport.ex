defmodule StubTransport do
  @moduledoc """
  Simple mock transport for MCP protocol testing.
  Records all messages sent through it for inspection in tests.
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  alias Hermes.MCP.Builders

  @type state :: %{
          messages: [String.t()],
          client: GenServer.name() | nil
        }

  @doc """
  Starts the mock transport.

  ## Options
  - `:name` - Process name (defaults to __MODULE__)
  """
  @impl true
  def start_link(opts \\ []) do
    if name = opts[:name] do
      GenServer.start_link(__MODULE__, %{messages: [], client: nil}, name: name)
    else
      GenServer.start_link(__MODULE__, %{messages: [], client: nil})
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
  def send_message(transport \\ __MODULE__, message) do
    GenServer.call(transport, {:send_message, message})
  end

  @impl true
  def shutdown(transport \\ __MODULE__) do
    GenServer.call(transport, :shutdown)
  end

  @impl true
  def supported_protocol_versions do
    ["2024-11-05", "2025-03-26"]
  end

  @impl true
  def init(state) do
    {:ok, state}
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
    {:reply, :ok, %{state | client: client}}
  end

  def handle_call(:count, _from, state) do
    {:reply, length(state.messages), state}
  end

  def handle_call({:send_message, message}, _from, state) do
    new_messages = [message | state.messages]
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
end
