defmodule MCPTest.MockTransport do
  @moduledoc """
  Unified mock transport for MCP protocol testing.

  Provides a single mock transport implementation that can be used for both
  client and server testing. Supports message recording, expectations, and
  verification patterns for different testing scenarios.

  ## Usage

  For client testing with mocking libraries:

      client = setup_client(transport: [layer: MCPTest.MockTransport, name: :test_transport])
      
  For server testing with message recording:

      {:ok, transport} = MCPTest.MockTransport.start_link(name: :server_transport)
      server = setup_server(transport: [layer: MCPTest.MockTransport, name: :server_transport])
      
      messages = MCPTest.MockTransport.get_messages(:server_transport)
  """

  @behaviour Hermes.Transport.Behaviour

  use GenServer

  alias Hermes.MCP.Message

  @type state :: %{
          messages: [String.t()],
          expectations: [expectation()],
          mode: :recording | :mocking
        }

  @type expectation :: %{
          method: String.t() | nil,
          params: map() | nil,
          response: term(),
          called: boolean()
        }

  @doc """
  Starts the mock transport.

  ## Options

  - `:name` - Process name (defaults to __MODULE__)
  - `:mode` - `:recording` (default) or `:mocking`
  """
  @impl true
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    mode = opts[:mode] || :recording
    GenServer.start_link(__MODULE__, %{messages: [], expectations: [], mode: mode}, name: name)
  end

  @doc """
  Gets all messages sent through this transport.
  """
  def get_messages(transport \\ __MODULE__) do
    GenServer.call(transport, :get_messages)
  end

  @doc """
  Clears all recorded messages.
  """
  def clear_messages(transport \\ __MODULE__) do
    GenServer.call(transport, :clear_messages)
  end

  @doc """
  Sets up an expectation for a specific method call.

  ## Examples

      expect_method(transport, "ping", %{}, fn -> :ok end)
      expect_method(transport, "resources/list", %{"cursor" => "abc"}, &handle_resources/1)
  """
  def expect_method(transport \\ __MODULE__, method, params \\ nil, response_fun) do
    expectation = %{
      method: method,
      params: params,
      response: response_fun,
      called: false
    }

    GenServer.call(transport, {:add_expectation, expectation})
  end

  @doc """
  Verifies that all expectations were called.
  """
  def verify_expectations(transport \\ __MODULE__) do
    GenServer.call(transport, :verify_expectations)
  end

  @doc """
  Gets the count of messages sent.
  """
  def message_count(transport \\ __MODULE__) do
    GenServer.call(transport, :message_count)
  end

  @doc """
  Gets the last message sent.
  """
  def last_message(transport \\ __MODULE__) do
    GenServer.call(transport, :last_message)
  end

  @doc """
  Finds messages matching a specific pattern.

  ## Examples

      find_messages(transport, method: "ping")
      find_messages(transport, method: "tools/call", params_contain: %{"name" => "my_tool"})
  """
  def find_messages(transport \\ __MODULE__, filters) do
    messages = get_messages(transport)

    Enum.filter(messages, fn message ->
      case Message.decode(message) do
        {:ok, [decoded]} -> matches_filters?(decoded, filters)
        _ -> false
      end
    end)
  end

  @impl true
  def send_message(transport, message) do
    GenServer.call(transport, {:send_message, message})
  end

  @impl true
  def shutdown(transport) do
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
    {:reply, Enum.reverse(state.messages), state}
  end

  @impl true
  def handle_call(:clear_messages, _from, state) do
    {:reply, :ok, %{state | messages: []}}
  end

  @impl true
  def handle_call({:add_expectation, expectation}, _from, state) do
    new_expectations = [expectation | state.expectations]
    {:reply, :ok, %{state | expectations: new_expectations}}
  end

  @impl true
  def handle_call(:verify_expectations, _from, state) do
    uncalled = Enum.reject(state.expectations, & &1.called)

    case uncalled do
      [] -> {:reply, :ok, state}
      missed -> {:reply, {:error, {:uncalled_expectations, missed}}, state}
    end
  end

  @impl true
  def handle_call(:message_count, _from, state) do
    {:reply, length(state.messages), state}
  end

  @impl true
  def handle_call(:last_message, _from, state) do
    last = List.first(state.messages)
    {:reply, last, state}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    new_messages = [message | state.messages]
    new_state = %{state | messages: new_messages}

    response =
      case state.mode do
        :mocking -> handle_expectations(message, state.expectations)
        :recording -> :ok
      end

    {:reply, response, new_state}
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    {:stop, :normal, :ok, state}
  end

  defp handle_expectations(message, expectations) do
    case Message.decode(message) do
      {:ok, [%{"method" => method, "params" => params}]} ->
        find_and_call_expectation(method, params, expectations)

      {:ok, [%{"method" => method}]} ->
        find_and_call_expectation(method, %{}, expectations)

      _ ->
        :ok
    end
  end

  defp find_and_call_expectation(method, params, expectations) do
    case Enum.find(expectations, &matches_expectation?(&1, method, params)) do
      %{response: response_fun} when is_function(response_fun, 0) ->
        response_fun.()

      %{response: response_fun} when is_function(response_fun, 1) ->
        response_fun.(params)

      %{response: response} ->
        response

      nil ->
        :ok
    end
  end

  defp matches_expectation?(%{method: expected_method, params: expected_params}, method, params) do
    method_matches = expected_method == nil or expected_method == method
    params_match = expected_params == nil or expected_params == params

    method_matches and params_match
  end

  defp matches_filters?(decoded, filters) do
    Enum.all?(filters, fn
      {:method, expected_method} ->
        decoded["method"] == expected_method

      {:params, expected_params} ->
        decoded["params"] == expected_params

      {:params_contain, partial_params} ->
        params = decoded["params"] || %{}

        Enum.all?(partial_params, fn {key, value} ->
          params[key] == value
        end)

      {:has_field, field} ->
        Map.has_key?(decoded, field)

      _ ->
        true
    end)
  end

  @doc """
  Asserts that a specific method was called.
  """
  def assert_method_called(transport \\ __MODULE__, method, params \\ nil) do
    import ExUnit.Assertions

    messages = find_messages(transport, method: method)
    found = check_method_called(messages, params)

    assert found, build_method_assert_message(method, params)
  end

  defp check_method_called(messages, nil), do: length(messages) > 0

  defp check_method_called(messages, params) do
    Enum.any?(messages, fn message ->
      case Message.decode(message) do
        {:ok, [%{"params" => ^params}]} -> true
        _ -> false
      end
    end)
  end

  defp build_method_assert_message(method, nil) do
    "Expected method '#{method}' to be called"
  end

  defp build_method_assert_message(method, params) do
    "Expected method '#{method}' to be called with params #{inspect(params)}"
  end

  @doc """
  Asserts that no messages were sent.
  """
  def assert_no_messages(transport \\ __MODULE__) do
    import ExUnit.Assertions

    count = message_count(transport)
    assert count == 0, "Expected no messages, but #{count} were sent"
  end

  @doc """
  Asserts that exactly N messages were sent.
  """
  def assert_message_count(transport \\ __MODULE__, expected_count) do
    import ExUnit.Assertions

    actual_count = message_count(transport)
    assert actual_count == expected_count, "Expected #{expected_count} messages, got #{actual_count}"
  end
end
