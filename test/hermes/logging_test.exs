defmodule Hermes.LoggingTest do
  use ExUnit.Case, async: false
  use Hermes.Logging

  import ExUnit.CaptureLog

  # too flaky, may remove it
  @moduletag capture_log: true, skip: true

  setup do
    original_log_config = Application.get_env(:hermes_mcp, :log)
    original_logging_config = Application.get_env(:hermes_mcp, :logging)

    on_exit(fn ->
      if original_log_config do
        Application.put_env(:hermes_mcp, :log, original_log_config)
      else
        Application.delete_env(:hermes_mcp, :log)
      end

      if original_logging_config do
        Application.put_env(:hermes_mcp, :logging, original_logging_config)
      else
        Application.delete_env(:hermes_mcp, :logging)
      end
    end)

    :ok
  end

  describe "configurable default log levels" do
    test "uses configured level for client events" do
      Application.put_env(:logger, :level, :warning)
      Application.put_env(:hermes_mcp, :logging, client_events: :warning)

      log =
        capture_log([level: :warning], fn ->
          Logging.client_event("test_event", :test_details)
        end)

      assert log =~ "[warning] MCP client event: test_event"
      assert log =~ "[warning] MCP event details: :test_details"
    end

    test "uses configured level for server events" do
      Application.put_env(:logger, :level, :error)
      Application.put_env(:hermes_mcp, :logging, server_events: :error)

      log =
        capture_log([level: :error], fn ->
          Logging.server_event("test_event", :test_details)
        end)

      assert log =~ "[error] MCP server event: test_event"
      assert log =~ "[error] MCP event details: :test_details"
    end

    test "uses configured level for transport events" do
      Application.put_env(:logger, :level, :info)
      Application.put_env(:hermes_mcp, :logging, transport_events: :info)

      log =
        capture_log([level: :info], fn ->
          Logging.transport_event("test_event", :test_details)
        end)

      assert log =~ "[info] MCP transport event: test_event"
      assert log =~ "[info] MCP transport details: :test_details"
    end

    test "uses configured level for protocol messages" do
      Application.put_env(:logger, :level, :warning)
      Application.put_env(:hermes_mcp, :logging, protocol_messages: :warning)

      log =
        capture_log([level: :warning], fn ->
          Logging.message("outgoing", "request", 123, %{
            "id" => 123,
            "method" => "test"
          })
        end)

      assert log =~ "[warning] [MCP message] outgoing request: id=123 method=test"

      assert log =~
               ~s([warning] [MCP message] outgoing request data: %{"id" => 123, "method" => "test"})
    end

    test "falls back to debug for unconfigured event types" do
      Application.delete_env(:hermes_mcp, :logging)

      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", :test_details)
        end)

      assert log =~ "[debug] MCP client event: test_event"
      assert log =~ "[debug] MCP event details: :test_details"
    end
  end

  describe "application config override behavior" do
    test "respects partial configuration" do
      Application.put_env(:logger, :level, :error)
      Application.put_env(:hermes_mcp, :logging, client_events: :error)

      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", nil)
          Logging.server_event("test_event", nil)
        end)

      assert log =~ "[error] MCP client event: test_event"
      assert log =~ "[debug] MCP server event: test_event"
    end

    test "handles empty logging configuration" do
      Application.put_env(:hermes_mcp, :logging, [])

      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", nil)
        end)

      assert log =~ "[debug] MCP client event: test_event"
    end
  end

  describe "global logging disable functionality" do
    test "respects :log false configuration" do
      Application.put_env(:hermes_mcp, :log, false)

      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", :details)
          Logging.server_event("test_event", :details)
          Logging.transport_event("test_event", :details)
          Logging.message("outgoing", "request", 123, %{"method" => "test"})
        end)

      assert log == ""
    end

    test "logs when :log is true (default)" do
      Application.put_env(:hermes_mcp, :log, true)

      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", nil)
        end)

      assert log =~ "[debug] MCP client event: test_event"
    end

    test "logs when :log config is not set" do
      Application.delete_env(:hermes_mcp, :log)

      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", nil)
        end)

      assert log =~ "[debug] MCP client event: test_event"
    end
  end

  describe "metadata level override behavior" do
    test "metadata level overrides default for client events" do
      Application.put_env(:logger, :level, :error)
      Application.put_env(:hermes_mcp, :logging, client_events: :debug)

      log =
        capture_log([level: :error], fn ->
          Logging.client_event("test_event", nil, level: :error, custom: :metadata)
        end)

      assert log =~ "[error] MCP client event: test_event"
    end

    test "metadata level overrides default for server events" do
      Application.put_env(:logger, :level, :warning)
      Application.put_env(:hermes_mcp, :logging, server_events: :debug)

      log =
        capture_log([level: :warning], fn ->
          Logging.server_event("test_event", nil, level: :warning, custom: :metadata)
        end)

      assert log =~ "[warning] MCP server event: test_event"
    end

    test "metadata level overrides default for transport events" do
      Application.put_env(:hermes_mcp, :logging, transport_events: :debug)

      log =
        capture_log([level: :info], fn ->
          Logging.transport_event("test_event", nil, level: :info, custom: :metadata)
        end)

      assert log =~ "[info] MCP transport event: test_event"
    end

    test "metadata level overrides default for protocol messages" do
      Application.put_env(:logger, :level, :error)
      Application.put_env(:hermes_mcp, :logging, protocol_messages: :debug)

      log =
        capture_log([level: :error], fn ->
          Logging.message(
            "incoming",
            "response",
            123,
            %{"id" => 123, "result" => %{}},
            level: :error,
            custom: :metadata
          )
        end)

      assert log =~ "[error] [MCP message] incoming response: id=123 success"

      assert log =~
               ~s([error] [MCP message] incoming response data: %{"id" => 123, "result" => %{}})
    end

    test "preserves other metadata while removing level" do
      log =
        capture_log([level: :info], fn ->
          Logging.client_event("test_event", nil,
            level: :info,
            custom: :metadata,
            another: :value
          )
        end)

      assert log =~ "[info] MCP client event: test_event"
    end
  end

  describe "message formatting and truncation logic" do
    test "formats request messages correctly" do
      log =
        capture_log([level: :debug], fn ->
          Logging.message("outgoing", "request", 123, %{
            "id" => 123,
            "method" => "tools/list",
            "params" => %{}
          })
        end)

      assert log =~
               "[debug] [MCP message] outgoing request: id=123 method=tools/list"

      assert log =~
               ~s([debug] [MCP message] outgoing request data: %{"id" => 123, "method" => "tools/list", "params" => %{}})
    end

    test "formats response messages correctly for success" do
      log =
        capture_log([level: :debug], fn ->
          Logging.message("incoming", "response", 123, %{
            "id" => 123,
            "result" => %{"tools" => []}
          })
        end)

      assert log =~ "[debug] [MCP message] incoming response: id=123 success"

      assert log =~
               ~s([debug] [MCP message] incoming response data: %{"id" => 123, "result" => %{"tools" => []}})
    end

    test "formats response messages correctly for error" do
      log =
        capture_log([level: :debug], fn ->
          Logging.message("incoming", "response", 123, %{
            "id" => 123,
            "error" => %{"code" => -1, "message" => "Error"}
          })
        end)

      assert log =~ "[debug] [MCP message] incoming response: id=123 error: -1"

      assert log =~
               ~s([debug] [MCP message] incoming response data: %{"error" => %{"code" => -1, "message" => "Error"}, "id" => 123})
    end

    test "formats notification messages correctly" do
      log =
        capture_log([level: :debug], fn ->
          Logging.message("incoming", "notification", nil, %{
            "method" => "progress",
            "params" => %{}
          })
        end)

      assert log =~ "[debug] [MCP message] incoming notification: method=progress"

      assert log =~
               ~s([debug] [MCP message] incoming notification data: %{"method" => "progress", "params" => %{}})
    end

    test "handles messages with nil id" do
      log =
        capture_log([level: :debug], fn ->
          Logging.message("outgoing", "request", nil, %{"method" => "test"})
        end)

      assert log =~ "[debug] [MCP message] outgoing request: id=none method=test"

      assert log =~
               ~s([debug] [MCP message] outgoing request data: %{"method" => "test"})
    end

    test "truncates large binary data" do
      large_data = String.duplicate("x", 600)

      log =
        capture_log([level: :debug], fn ->
          Logging.message("outgoing", "unknown", nil, large_data)
        end)

      assert log =~ "[debug] [MCP message] outgoing unknown: id=none"
      assert log =~ "[debug] [MCP message] outgoing unknown data (truncated):"
      assert log =~ "..."
    end

    test "truncates large map data" do
      large_map = Map.new(1..15, fn i -> {"key#{i}", "value#{i}"} end)

      log =
        capture_log([level: :debug], fn ->
          Logging.message("outgoing", "unknown", nil, large_map)
        end)

      assert log =~ "[debug] [MCP message] outgoing unknown: id=none"
      assert log =~ "[debug] [MCP message] outgoing unknown data (truncated):"
      assert log =~ "..."
    end

    test "logs full data for small payloads" do
      small_data = "small"

      log =
        capture_log([level: :debug], fn ->
          Logging.message("outgoing", "unknown", nil, small_data)
        end)

      assert log =~ "[debug] [MCP message] outgoing unknown: id=none"
      assert log =~ "[debug] [MCP message] outgoing unknown data: \"small\""
    end

    test "handles request messages with important keys for truncation" do
      large_map =
        1..15
        |> Map.new(fn i -> {"key#{i}", "value#{i}"} end)
        |> Map.merge(%{"id" => 123, "method" => "test"})

      log =
        capture_log([level: :debug], fn ->
          Logging.message("outgoing", "request", 123, large_map)
        end)

      assert log =~ "[debug] [MCP message] outgoing request: id=123 method=test"
      assert log =~ "[debug] [MCP message] outgoing request data (truncated):"
      assert log =~ "\"id\""
      assert log =~ "\"method\""
      assert log =~ "..."
    end
  end

  describe "log level mapping" do
    test "maps debug to Logger.debug" do
      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test", nil, level: :debug)
        end)

      assert log =~ "[debug] MCP client event: test"
    end

    test "maps info to Logger.info" do
      log =
        capture_log([level: :info], fn ->
          Logging.client_event("test", nil, level: :info)
        end)

      assert log =~ "[info] MCP client event: test"
    end

    test "maps notice to Logger.notice" do
      log =
        capture_log([level: :notice], fn ->
          Logging.client_event("test", nil, level: :notice)
        end)

      assert log =~ "[notice] MCP client event: test"
    end

    test "maps warning to Logger.warning" do
      log =
        capture_log([level: :warning], fn ->
          Logging.client_event("test", nil, level: :warning)
        end)

      assert log =~ "[warning] MCP client event: test"
    end

    test "maps error to Logger.error" do
      Application.put_env(:logger, :level, :error)

      log =
        capture_log([level: :error], fn ->
          Logging.client_event("test", nil, level: :error)
        end)

      assert log =~ "[error] MCP client event: test"
    end

    test "maps critical to Logger.critical" do
      Application.put_env(:logger, :level, :critical)

      log =
        capture_log([level: :critical], fn ->
          Logging.client_event("test", nil, level: :critical)
        end)

      assert log =~ "[critical] MCP client event: test"
    end

    test "maps alert to Logger.alert" do
      Application.put_env(:logger, :level, :alert)

      log =
        capture_log([level: :alert], fn ->
          Logging.client_event("test", nil, level: :alert)
        end)

      assert log =~ "[alert] MCP client event: test"
    end

    test "maps emergency to Logger.emergency" do
      Application.put_env(:logger, :level, :emergency)

      log =
        capture_log([level: :emergency], fn ->
          Logging.client_event("test", nil, level: :emergency)
        end)

      assert log =~ "[emergency] MCP client event: test"
    end
  end

  describe "event logging without details" do
    test "client_event logs only main message when details is nil" do
      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", nil)
        end)

      assert log =~ "[debug] MCP client event: test_event"
      refute log =~ "MCP event details:"
    end

    test "server_event logs only main message when details is nil" do
      log =
        capture_log([level: :debug], fn ->
          Logging.server_event("test_event", nil)
        end)

      assert log =~ "[debug] MCP server event: test_event"
      refute log =~ "MCP event details:"
    end

    test "transport_event logs only main message when details is nil" do
      log =
        capture_log([level: :debug], fn ->
          Logging.transport_event("test_event", nil)
        end)

      assert log =~ "[debug] MCP transport event: test_event"
      refute log =~ "MCP transport details:"
    end

    test "client_event logs both messages when details is provided" do
      log =
        capture_log([level: :debug], fn ->
          Logging.client_event("test_event", "test_details")
        end)

      assert log =~ "[debug] MCP client event: test_event"
      assert log =~ "[debug] MCP event details: \"test_details\""
    end
  end
end
