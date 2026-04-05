defmodule DeferredStubServer do
  @moduledoc """
  Test server that supports deferred tool call replies.

  Tools:
  - "deferred_tool" - defers, sends {:deferred_registered, ref} to registered test pid
  - "deferred_tool_with_cancel" - same but includes cancel_notify option
  - "deferred_tool_check_pid" - also sends {:server_pid, pid}

  Before calling tools, register the test pid via:
    DeferredStubServer.register_test_pid(self())
  """

  use Hermes.Server,
    name: "Deferred Test Server",
    version: "1.0.0",
    capabilities: [:tools]

  import Hermes.Server.Frame

  alias Hermes.MCP.Error

  # Simple process-based test pid registry using a named Agent
  def register_test_pid(pid) do
    case Process.whereis(:deferred_test_registry) do
      nil ->
        Agent.start_link(fn -> pid end, name: :deferred_test_registry)

      _existing ->
        Agent.update(:deferred_test_registry, fn _ -> pid end)
    end

    :ok
  end

  defp get_test_pid do
    Agent.get(:deferred_test_registry, & &1)
  end

  @impl true
  def init(_client_info, frame) do
    frame =
      frame
      |> register_tool("deferred_tool",
        description: "A tool that defers its reply",
        input_schema: %{type: "object", properties: %{}}
      )
      |> register_tool("deferred_tool_with_cancel",
        description: "A tool that defers with cancel notify",
        input_schema: %{type: "object", properties: %{}}
      )
      |> register_tool("deferred_tool_check_pid",
        description: "A tool that checks server_pid in frame",
        input_schema: %{type: "object", properties: %{}}
      )

    {:ok, frame}
  end

  @impl true
  def handle_tool_call("deferred_tool", _args, frame) do
    ref = make_ref()
    test_pid = get_test_pid()
    send(test_pid, {:deferred_registered, ref})
    {:defer, ref, %{}, frame}
  end

  def handle_tool_call("deferred_tool_with_cancel", _args, frame) do
    ref = make_ref()
    test_pid = get_test_pid()
    send(test_pid, {:deferred_registered, ref})
    {:defer, ref, %{cancel_notify: test_pid}, frame}
  end

  def handle_tool_call("deferred_tool_check_pid", _args, frame) do
    ref = make_ref()
    test_pid = get_test_pid()
    server_pid = frame.private[:server_pid]
    send(test_pid, {:server_pid, server_pid})
    send(test_pid, {:deferred_registered, ref})
    {:defer, ref, %{}, frame}
  end

  def handle_tool_call(name, _args, frame) do
    {:error, Error.protocol(:invalid_request, %{message: "Unknown tool: #{name}"}), frame}
  end

  @impl true
  def handle_notification(_notification, frame) do
    {:noreply, frame}
  end
end
