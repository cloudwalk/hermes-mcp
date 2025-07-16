defmodule Hermes.MCP.ResponseTest do
  use ExUnit.Case, async: true

  alias Hermes.MCP.Response

  @moduletag capture_log: true

  doctest Response

  describe "from_json_rpc/1" do
    test "creates a response from a JSON-RPC response" do
      json_response = %{
        "jsonrpc" => "2.0",
        "result" => %{"data" => "value"},
        "id" => "req_123"
      }

      response = Response.from_json_rpc(json_response)

      assert response.result == %{"data" => "value"}
      assert response.id == "req_123"
      assert response.is_error == false
    end

    test "detects domain errors with isError field" do
      json_response = %{
        "jsonrpc" => "2.0",
        "result" => %{"isError" => true, "reason" => "not_found"},
        "id" => "req_123"
      }

      response = Response.from_json_rpc(json_response)

      assert response.result == %{"isError" => true, "reason" => "not_found"}
      assert response.id == "req_123"
      assert response.is_error == true
    end

    test "handles non-map results" do
      # This should not happen in practice with MCP, but testing for robustness
      json_response = %{
        "jsonrpc" => "2.0",
        "result" => "string_result",
        "id" => "req_123"
      }

      response = Response.from_json_rpc(json_response)

      assert response.result == "string_result"
      assert response.id == "req_123"
      assert response.is_error == false
    end
  end

  describe "unwrap/1" do
    test "returns the raw result for any response" do
      success_response = %Response{
        result: %{"data" => "value"},
        id: "req_123",
        is_error: false
      }

      error_response = %Response{
        result: %{"isError" => true, "reason" => "not_found"},
        id: "req_123",
        is_error: true
      }

      assert Response.unwrap(success_response) == %{"data" => "value"}

      assert Response.unwrap(error_response) == %{
               "isError" => true,
               "reason" => "not_found"
             }
    end
  end

  describe "success?/1" do
    test "returns true for successful responses" do
      response = %Response{
        result: %{"data" => "value"},
        id: "req_123",
        is_error: false
      }

      assert Response.success?(response) == true
    end

    test "returns false for domain errors" do
      response = %Response{
        result: %{"isError" => true},
        id: "req_123",
        is_error: true
      }

      assert Response.success?(response) == false
    end
  end

  describe "error?/1" do
    test "returns false for successful responses" do
      response = %Response{
        result: %{"data" => "value"},
        id: "req_123",
        is_error: false
      }

      assert Response.error?(response) == false
    end

    test "returns true for domain errors" do
      response = %Response{
        result: %{"isError" => true},
        id: "req_123",
        is_error: true
      }

      assert Response.error?(response) == true
    end
  end

  describe "get_result/1" do
    test "returns the raw result regardless of error status" do
      success_response = %Response{
        result: %{"data" => "value"},
        id: "req_123",
        is_error: false
      }

      error_response = %Response{
        result: %{"isError" => true, "reason" => "not_found"},
        id: "req_123",
        is_error: true
      }

      assert Response.get_result(success_response) == %{"data" => "value"}

      assert Response.get_result(error_response) == %{
               "isError" => true,
               "reason" => "not_found"
             }
    end
  end

  describe "get_id/1" do
    test "returns the request ID" do
      response = %Response{
        result: %{},
        id: "req_123",
        is_error: false
      }

      assert Response.get_id(response) == "req_123"
    end
  end
end
