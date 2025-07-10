defmodule Hermes.ClientTest do
  use ExUnit.Case, async: true

  alias Hermes.Client.Session
  alias Hermes.MCP.Builders

  describe "StubClient callbacks" do
    test "init callback is called" do
      server_info = %{"name" => "TestServer", "version" => "1.0.0"}
      session = Session.new()

      {:ok, updated_session} = StubClient.init(server_info, session)

      assert updated_session.assigns[:init_called] == true
      assert updated_session.assigns[:server_info] == server_info
    end

    test "handle_progress callback" do
      session = Session.assign(Session.new(), :test_pid, self())

      {:noreply, updated_session} = StubClient.handle_progress("token", 50, 100, session)

      assert_receive {:progress_received, "token", 50, 100}, 500
      assert updated_session.assigns[:last_progress] == {"token", 50, 100}
    end

    test "handle_progress callback without total" do
      session = Session.assign(Session.new(), :test_pid, self())

      {:noreply, updated_session} = StubClient.handle_progress("token", 75, nil, session)

      assert_receive {:progress_received, "token", 75, nil}, 500
      assert updated_session.assigns[:last_progress] == {"token", 75, nil}
    end

    test "handle_log callback" do
      session = Session.assign(Session.new(), :test_pid, self())

      {:noreply, updated_session} =
        StubClient.handle_log("error", "Test error", "logger", session)

      assert_receive {:log_received, "error", "Test error", "logger"}, 500
      assert updated_session.assigns[:last_log] == {"error", "Test error", "logger"}
    end

    test "handle_sampling callback returns response" do
      session = Session.assign(Session.new(), :test_pid, self())

      messages = [
        %{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}
      ]

      model_prefs = %{"hints" => [%{"name" => "claude-3"}]}

      {:reply, result, updated_session} =
        StubClient.handle_sampling(messages, model_prefs, %{}, session)

      assert_receive {:sampling_request, ^messages, ^model_prefs}, 500
      assert result["role"] == "assistant"
      assert result["model"] == "stub-model"

      assert updated_session.assigns[:last_sampling_request] ==
               {messages, model_prefs, %{}}
    end

    test "handle_sampling callback returns error when configured" do
      session =
        Session.new()
        |> Session.assign(:test_pid, self())
        |> Session.assign(:sampling_error, true)

      {:error, "Sampling failed", _session} =
        StubClient.handle_sampling([], %{}, %{}, session)
    end

    test "handle_info callback" do
      session = Session.assign(Session.new(), :test_pid, self())

      {:noreply, updated_session} = StubClient.handle_info({:custom, "data"}, session)

      assert_receive {:info_received, {:custom, "data"}}, 500
      assert updated_session.assigns[:last_info] == {:custom, "data"}
    end

    test "handle_call callback" do
      session = Session.assign(Session.new(), :test_pid, self())
      from = {self(), make_ref()}

      {:reply, :stub_reply, updated_session} =
        StubClient.handle_call(:test_request, from, session)

      assert_receive {:call_received, :test_request, ^from}, 500
      assert updated_session.assigns[:last_call] == {:test_request, from}
    end

    test "handle_cast callback" do
      session = Session.assign(Session.new(), :test_pid, self())

      {:noreply, updated_session} = StubClient.handle_cast({:test_cast, 123}, session)

      assert_receive {:cast_received, {:test_cast, 123}}, 500
      assert updated_session.assigns[:last_cast] == {:test_cast, 123}
    end

    test "terminate callback" do
      session = Session.assign(Session.new(), :test_pid, self())

      :ok = StubClient.terminate(:normal, session)

      assert_receive {:terminated, :normal}, 500
    end
  end

  describe "StubClient helper functions" do
    setup do
      {:ok, client} =
        GenServer.start_link(StubClient, Session.new(), name: :test_stub_client)

      %{client: client}
    end

    test "configure_test_pid", %{client: client} do
      assert :ok = StubClient.configure_test_pid(client, self())

      session = StubClient.get_session(client)
      assert session.assigns[:test_pid] == self()
    end

    test "configure_sampling_error", %{client: client} do
      assert :ok = StubClient.configure_sampling_error(client, true)

      session = StubClient.get_session(client)
      assert session.assigns[:sampling_error] == true
    end

    test "get_session", %{client: client} do
      session = StubClient.get_session(client)
      assert %Session{} = session
    end
  end
end
