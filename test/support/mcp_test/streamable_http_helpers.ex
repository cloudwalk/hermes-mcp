defmodule MCPTest.StreamableHTTPHelpers do
  @moduledoc """
  Helper functions specifically for StreamableHTTP transport testing.

  Since StreamableHTTP transport requires direct message handling with the server,
  this module provides helpers to properly initialize sessions and handle messages.
  """

  import MCPTest.Builders

  alias Hermes.Server.Transport.StreamableHTTP

  @doc """
  Initializes a session for StreamableHTTP transport testing.

  This handles the MCP initialization handshake required before
  the server will accept other requests.

  ## Examples

      initialize_session(transport, "session-123")
      initialize_session(transport, "session-456", client_info: %{"name" => "MyClient"})
  """
  def initialize_session(transport, session_id, opts \\ []) do
    init_request = init_request(opts)
    {:ok, init_response} = StreamableHTTP.handle_message(transport, session_id, init_request)

    if is_nil(init_response) do
      raise "Failed to initialize session: #{inspect(init_response)}"
    end

    notification = initialized_notification()
    {:ok, nil} = StreamableHTTP.handle_message(transport, session_id, notification)

    :ok
  end

  @doc """
  Sends a request to the transport and returns the response.

  Automatically handles session initialization if not already done.

  ## Examples

      {:ok, response} = send_request(transport, "session-123", ping_request())
      {:ok, response} = send_request(transport, "session-456", tools_list_request())
  """
  def send_request(transport, session_id, request, opts \\ []) do
    if Keyword.get(opts, :initialize, should_initialize?(request)) do
      case initialize_session(transport, session_id, opts) do
        :ok -> :ok
        error -> {:error, {:initialization_failed, error}}
      end
    end

    StreamableHTTP.handle_message(transport, session_id, request)
  end

  @doc """
  Sends a request and handles SSE routing if handler is registered.

  ## Examples

      # Without SSE handler
      {:ok, response} = send_request_for_sse(transport, "session-123", ping_request())
      
      # With SSE handler
      StreamableHTTP.register_sse_handler(transport, "session-123")
      {:sse, response} = send_request_for_sse(transport, "session-123", ping_request())
  """
  def send_request_for_sse(transport, session_id, request, opts \\ []) do
    if Keyword.get(opts, :initialize, should_initialize?(request)) do
      initialize_session(transport, session_id, opts)
    end

    StreamableHTTP.handle_message_for_sse(transport, session_id, request)
  end

  @doc """
  Sets up multiple sessions with SSE handlers for testing broadcasts.

  ## Examples

      sessions = setup_broadcast_sessions(transport, 3)
      # Returns: [{"session-1", pid1}, {"session-2", pid2}, {"session-3", pid3}]
  """
  def setup_broadcast_sessions(transport, count, collector_pid) do
    for i <- 1..count do
      session_id = "session-#{i}-#{System.unique_integer([:positive])}"

      pid =
        spawn(fn ->
          receive do
            {:sse_message, msg} -> send(collector_pid, {:received, self(), msg})
            :stop -> :ok
          end
        end)

      :ok = GenServer.call(transport, {:register_sse_handler, session_id, pid})
      {session_id, pid}
    end
  end

  @doc """
  Cleans up spawned processes from tests.
  """
  def cleanup_sessions(session_pids) do
    for {_session_id, pid} <- session_pids do
      if Process.alive?(pid) do
        send(pid, :stop)
      end
    end
  end

  # Private helpers

  defp should_initialize?(%{"method" => "initialize"}), do: false
  defp should_initialize?(%{"method" => "ping"}), do: false
  defp should_initialize?(%{"method" => "notifications/" <> _}), do: false
  defp should_initialize?(_), do: true
end
