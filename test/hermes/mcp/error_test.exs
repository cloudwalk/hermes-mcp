defmodule Hermes.MCP.ErrorTest do
  use ExUnit.Case, async: true

  alias Hermes.MCP.Error

  @moduletag capture_log: true

  doctest Hermes.MCP.Error

  describe "standard JSON-RPC errors" do
    test "parse_error/1 creates the correct error structure" do
      error = Error.parse_error()
      assert error.code == -32_700
      assert error.reason == :parse_error
      assert error.data == %{}

      error = Error.parse_error(%{line: 10, column: 5})
      assert error.data == %{line: 10, column: 5}
    end

    test "invalid_request/1 creates the correct error structure" do
      error = Error.invalid_request()
      assert error.code == -32_600
      assert error.reason == :invalid_request
    end

    test "method_not_found/1 creates the correct error structure" do
      error = Error.method_not_found(%{method: "unknown"})
      assert error.code == -32_601
      assert error.reason == :method_not_found
      assert error.data.method == "unknown"
    end

    test "invalid_params/1 creates the correct error structure" do
      error = Error.invalid_params()
      assert error.code == -32_602
      assert error.reason == :invalid_params
    end

    test "internal_error/1 creates the correct error structure" do
      error = Error.internal_error()
      assert error.code == -32_603
      assert error.reason == :internal_error
    end
  end

  describe "transport errors" do
    test "transport_error/2 creates the correct error structure" do
      error = Error.transport_error(:connection_refused)
      assert error.code == -32_000
      assert error.reason == :connection_refused
      assert error.data.type == :transport

      error = Error.transport_error(:timeout, %{elapsed_ms: 5000})
      assert error.reason == :timeout
      assert error.data.type == :transport
      assert error.data.elapsed_ms == 5000
    end
  end

  describe "client errors" do
    test "client_error/2 creates the correct error structure" do
      error = Error.client_error(:request_timeout)
      assert error.code == -32_000
      assert error.reason == :request_timeout
      assert error.data.type == :client

      error = Error.client_error(:initialization_failed, %{reason: "missing capabilities"})
      assert error.reason == :initialization_failed
      assert error.data.type == :client
      assert error.data.reason == "missing capabilities"
    end
  end

  describe "JSON-RPC error conversion" do
    test "from_json_rpc/1 converts standard error codes to reasons" do
      json_error = %{"code" => -32_700, "message" => "Parse error"}
      error = Error.from_json_rpc(json_error)

      assert error.code == -32_700
      assert error.reason == :parse_error
      assert error.data.original_message == "Parse error"

      json_error = %{"code" => -32_600, "message" => "Invalid Request"}
      error = Error.from_json_rpc(json_error)
      assert error.reason == :invalid_request

      json_error = %{"code" => -32_601, "message" => "Method not found"}
      error = Error.from_json_rpc(json_error)
      assert error.reason == :method_not_found

      json_error = %{"code" => -32_602, "message" => "Invalid params"}
      error = Error.from_json_rpc(json_error)
      assert error.reason == :invalid_params

      json_error = %{"code" => -32_603, "message" => "Internal error"}
      error = Error.from_json_rpc(json_error)
      assert error.reason == :internal_error
    end

    test "from_json_rpc/1 handles server error codes" do
      json_error = %{"code" => -32_000, "message" => "Server error"}
      error = Error.from_json_rpc(json_error)

      assert error.code == -32_000
      assert error.reason == :server_error
    end

    test "from_json_rpc/1 includes data if present" do
      json_error = %{
        "code" => -32_000,
        "message" => "Server error",
        "data" => %{"details" => "Something went wrong"}
      }

      error = Error.from_json_rpc(json_error)

      assert error.data["details"] == "Something went wrong"
      assert error.data.original_message == "Server error"
    end
  end

  describe "utility functions" do
    test "to_tuple/1 converts an error to a tuple" do
      error = Error.parse_error()
      assert Error.to_tuple(error) == {:error, error}
    end
  end
end
