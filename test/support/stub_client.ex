defmodule StubClient do
  @moduledoc """
  Minimal test client that implements the behaviour callbacks.

  Used for testing client callback functionality.
  This client implements all optional callbacks for testing purposes.
  """

  use Hermes.Client,
    name: "StubClient",
    version: "1.0.0",
    protocol_version: "2025-03-26",
    capabilities: [:sampling]

  alias Hermes.Client.Session

  @impl true
  def init(server_info, session) do
    # Store server info in session for testing
    session = Session.assign(session, :server_info, server_info)
    session = Session.assign(session, :init_called, true)
    {:ok, session}
  end

  @impl true
  def handle_progress(token, progress, total, session) do
    # Store progress info for testing
    session = Session.assign(session, :last_progress, {token, progress, total})

    # Send to test process if configured
    if test_pid = session.assigns[:test_pid] do
      send(test_pid, {:progress_received, token, progress, total})
    end

    {:noreply, session}
  end

  @impl true
  def handle_log(level, data, logger, session) do
    # Store log info for testing
    session = Session.assign(session, :last_log, {level, data, logger})

    # Send to test process if configured
    if test_pid = session.assigns[:test_pid] do
      send(test_pid, {:log_received, level, data, logger})
    end

    {:noreply, session}
  end

  @impl true
  def handle_sampling(messages, model_preferences, opts, session) do
    # Store sampling request for testing
    session =
      Session.assign(session, :last_sampling_request, {messages, model_preferences, opts})

    # Send to test process if configured
    if test_pid = session.assigns[:test_pid] do
      send(test_pid, {:sampling_request, messages, model_preferences})
    end

    # Check if we should return an error (for testing error handling)
    if session.assigns[:sampling_error] do
      {:error, "Sampling failed", session}
    else
      # Return a sample response
      result = %{
        "model" => "stub-model",
        "stopReason" => "endTurn",
        "role" => "assistant",
        "content" => [
          %{
            "type" => "text",
            "text" => "Hello from stub client"
          }
        ]
      }

      {:reply, result, session}
    end
  end

  @impl true
  def handle_info(msg, session) do
    # Store info message for testing
    session = Session.assign(session, :last_info, msg)

    # Send to test process if configured
    if test_pid = session.assigns[:test_pid] do
      send(test_pid, {:info_received, msg})
    end

    {:noreply, session}
  end

  @impl true
  def handle_cast(request, session) do
    # Store cast request for testing
    session = Session.assign(session, :last_cast, request)

    # Send to test process if configured
    if test_pid = session.assigns[:test_pid] do
      send(test_pid, {:cast_received, request})
    end

    {:noreply, session}
  end

  @impl true
  def terminate(reason, session) do
    # Send termination to test process if configured
    if test_pid = session.assigns[:test_pid] do
      send(test_pid, {:terminated, reason})
    end

    :ok
  end

  # Test helper functions

  def configure_test_pid(client, test_pid) do
    GenServer.call(client, {:configure_test_pid, test_pid})
  end

  def configure_sampling_error(client, should_error) do
    GenServer.call(client, {:configure_sampling_error, should_error})
  end

  def get_session(client) do
    GenServer.call(client, :get_session)
  end

  # Handle the test configuration calls

  @impl true
  def handle_call({:configure_test_pid, test_pid}, _from, session) do
    updated_session = Session.assign(session, :test_pid, test_pid)
    {:reply, :ok, updated_session}
  end

  def handle_call({:configure_sampling_error, should_error}, _from, session) do
    updated_session = Session.assign(session, :sampling_error, should_error)
    {:reply, :ok, updated_session}
  end

  def handle_call(:get_session, _from, session) do
    {:reply, session, session}
  end

  def handle_call(request, from, session) do
    # Store call request for testing
    session = Session.assign(session, :last_call, {request, from})

    # Send to test process if configured
    if test_pid = session.assigns[:test_pid] do
      send(test_pid, {:call_received, request, from})
    end

    {:reply, :stub_reply, session}
  end
end
