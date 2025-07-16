defmodule Hermes.MCP.ErrorTest do
  use ExUnit.Case, async: true

  alias Hermes.MCP.Error

  @moduletag capture_log: true

  doctest Error

  describe "protocol errors" do
    test "protocol/2 creates parse error" do
      error = Error.protocol(:parse_error)
      assert error.code == -32_700
      assert error.reason == :parse_error
      assert error.message == "Parse error"
      assert error.data == %{}

      error = Error.protocol(:parse_error, %{line: 10, column: 5})
      assert error.data == %{line: 10, column: 5}
    end

    test "protocol/2 creates invalid request error" do
      error = Error.protocol(:invalid_request)
      assert error.code == -32_600
      assert error.reason == :invalid_request
      assert error.message == "Invalid Request"
    end

    test "protocol/2 creates method not found error" do
      error = Error.protocol(:method_not_found, %{method: "unknown"})
      assert error.code == -32_601
      assert error.reason == :method_not_found
      assert error.message == "Method not found"
      assert error.data.method == "unknown"
    end

    test "protocol/2 creates invalid params error" do
      error = Error.protocol(:invalid_params)
      assert error.code == -32_602
      assert error.reason == :invalid_params
      assert error.message == "Invalid params"
    end

    test "protocol/2 creates internal error" do
      error = Error.protocol(:internal_error)
      assert error.code == -32_603
      assert error.reason == :internal_error
      assert error.message == "Internal error"
    end
  end

  describe "transport errors" do
    test "transport/2 creates connection error" do
      error = Error.transport(:connection_refused)
      assert error.code == -32_000
      assert error.reason == :connection_refused
      assert error.message == "Connection Refused"
      assert error.data == %{}
    end

    test "transport/2 includes data" do
      error = Error.transport(:timeout, %{elapsed_ms: 5000})
      assert error.reason == :timeout
      assert error.message == "Timeout"
      assert error.data.elapsed_ms == 5000
    end
  end

  describe "resource errors" do
    test "resource/2 creates not found error" do
      error = Error.resource(:not_found, %{uri: "file:///missing.txt"})
      assert error.code == -32_002
      assert error.reason == :resource_not_found
      assert error.message == "Resource not found"
      assert error.data.uri == "file:///missing.txt"
    end
  end

  describe "execution errors" do
    test "execution/2 creates custom error" do
      error = Error.execution("Database connection failed")
      assert error.code == -32_000
      assert error.reason == :execution_error
      assert error.message == "Database connection failed"
      assert error.data == %{}
    end

    test "execution/2 includes data" do
      error = Error.execution("API rate limit exceeded", %{retry_after: 60})
      assert error.message == "API rate limit exceeded"
      assert error.data.retry_after == 60
    end
  end

  describe "JSON-RPC error conversion" do
    test "from_json_rpc/1 converts standard error codes" do
      json_error = %{"code" => -32_700, "message" => "Parse error"}
      error = Error.from_json_rpc(json_error)

      assert error.code == -32_700
      assert error.reason == :parse_error
      assert error.message == "Parse error"
      assert error.data == %{}
    end

    test "from_json_rpc/1 handles resource not found" do
      json_error = %{"code" => -32_002, "message" => "Not found"}
      error = Error.from_json_rpc(json_error)

      assert error.code == -32_002
      assert error.reason == :resource_not_found
    end

    test "from_json_rpc/1 includes data if present" do
      json_error = %{
        "code" => -32_000,
        "message" => "Server error",
        "data" => %{"details" => "Something went wrong"}
      }

      error = Error.from_json_rpc(json_error)

      assert error.data == %{"details" => "Something went wrong"}
      assert error.message == "Server error"
    end

    test "from_json_rpc/1 handles missing message" do
      json_error = %{"code" => -32_700}
      error = Error.from_json_rpc(json_error)

      assert error.code == -32_700
      assert error.reason == :parse_error
      assert error.message == nil
    end
  end

  describe "to_json_rpc/2" do
    test "encodes error correctly" do
      error = Error.protocol(:parse_error)
      {:ok, encoded} = Error.to_json_rpc(error, "req-123")

      decoded = Jason.decode!(encoded)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == "req-123"
      assert decoded["error"]["code"] == -32_700
      assert decoded["error"]["message"] == "Parse error"
    end

    test "includes data when present" do
      error = Error.protocol(:invalid_params, %{field: "name"})
      {:ok, encoded} = Error.to_json_rpc(error, 1)

      decoded = Jason.decode!(encoded)
      assert decoded["error"]["data"]["field"] == "name"
    end

    test "uses custom message when available" do
      error = Error.execution("Custom error message")
      {:ok, encoded} = Error.to_json_rpc(error, 1)

      decoded = Jason.decode!(encoded)
      assert decoded["error"]["message"] == "Custom error message"
    end
  end

  describe "inspect protocol" do
    test "formats error with message and data" do
      error = Error.execution("Not found", %{"code" => 404})
      inspected = inspect(error)

      assert String.contains?(inspected, "#MCP.Error<execution_error")
      assert String.contains?(inspected, "Not found")
      assert String.contains?(inspected, "404")
    end

    test "formats error with only message" do
      error = Error.protocol(:parse_error)
      inspected = inspect(error)

      assert String.contains?(inspected, "#MCP.Error<parse_error: Parse error>")
    end

    test "handles empty data" do
      error = %Error{reason: :empty_test, data: %{}}
      inspected = inspect(error)

      assert inspected == "#MCP.Error<empty_test>"
    end
  end
end
