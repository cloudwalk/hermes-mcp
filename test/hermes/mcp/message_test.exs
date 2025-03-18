defmodule Hermes.MCP.MessageTest do
  use ExUnit.Case, async: true

  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response

  @moduletag capture_log: true

  doctest Hermes.MCP.Message

  describe "decode/1" do
    test "decodes a valid JSON-RPC response" do
      json = ~s({"jsonrpc":"2.0","result":{},"id":"req_123"})

      assert {:ok, [message]} = Message.decode(json)
      assert message["jsonrpc"] == "2.0"
      assert message["result"] == %{}
      assert message["id"] == "req_123"
    end

    test "decodes multiple messages separated by newlines" do
      json = """
      {"jsonrpc":"2.0","result":{},"id":"req_1"}
      {"jsonrpc":"2.0","result":{},"id":"req_2"}
      """

      assert {:ok, messages} = Message.decode(json)
      assert length(messages) == 2
      assert Enum.at(messages, 0)["id"] == "req_1"
      assert Enum.at(messages, 1)["id"] == "req_2"
    end

    test "returns error for invalid JSON" do
      json = ~s({"jsonrpc":"2.0",invalid})

      assert {:error, error} = Message.decode(json)
      assert %Error{} = error
      assert error.reason == :parse_error
    end
  end

  describe "encode_request/2" do
    test "encodes a request with the correct structure" do
      request = %{"method" => "ping", "params" => %{}}
      id = "req_123"

      assert {:ok, json} = Message.encode_request(request, id)
      assert is_binary(json)

      # Verify the JSON structure
      assert {:ok, [decoded]} = Message.decode(json)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "ping"
      assert decoded["params"] == %{}
      assert decoded["id"] == "req_123"
    end

    test "appends a newline character" do
      {:ok, json} = Message.encode_request(%{"method" => "ping", "params" => %{}}, "req_123")
      assert String.ends_with?(json, "\n")
    end

    test "works with integer IDs" do
      {:ok, json} = Message.encode_request(%{"method" => "ping", "params" => %{}}, 123)

      assert {:ok, [decoded]} = Message.decode(json)
      assert decoded["id"] == 123
    end
  end

  describe "encode_notification/1" do
    test "encodes a notification with the correct structure" do
      notification = %{"method" => "notifications/progress", "params" => %{"progress" => 50}}

      assert {:ok, json} = Message.encode_notification(notification)
      assert is_binary(json)

      # Verify the JSON structure
      assert {:ok, [decoded]} = Message.decode(json)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "notifications/progress"
      assert decoded["params"]["progress"] == 50
      assert not Map.has_key?(decoded, "id")
    end

    test "appends a newline character" do
      {:ok, json} = Message.encode_notification(%{"method" => "notifications/progress", "params" => %{}})
      assert String.ends_with?(json, "\n")
    end
  end

  describe "encode_progress_notification/3" do
    test "encodes a progress notification with the correct structure" do
      assert {:ok, json} = Message.encode_progress_notification("token123", 50)

      assert {:ok, [decoded]} = Message.decode(json)
      assert decoded["method"] == "notifications/progress"
      assert decoded["params"]["progressToken"] == "token123"
      assert decoded["params"]["progress"] == 50
      assert not Map.has_key?(decoded["params"], "total")
    end

    test "includes total when provided" do
      assert {:ok, json} = Message.encode_progress_notification("token123", 50, 100)

      assert {:ok, [decoded]} = Message.decode(json)
      assert decoded["params"]["total"] == 100
    end

    test "works with integer tokens" do
      assert {:ok, json} = Message.encode_progress_notification(123, 50)

      assert {:ok, [decoded]} = Message.decode(json)
      assert decoded["params"]["progressToken"] == 123
    end
  end

  describe "validate/1" do
    test "validates a correct response" do
      message = %{"jsonrpc" => "2.0", "result" => %{}, "id" => "req_123"}
      assert :ok = Message.validate(message)
    end

    test "validates a correct error" do
      message = %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => -32_700, "message" => "Parse error"},
        "id" => "req_123"
      }

      assert :ok = Message.validate(message)
    end

    test "validates a correct request for known methods" do
      message = %{"jsonrpc" => "2.0", "method" => "ping", "params" => %{}, "id" => "req_123"}
      assert :ok = Message.validate(message)
    end

    test "validates a correct notification for known methods" do
      message = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/progress",
        "params" => %{"progress" => 50}
      }

      assert :ok = Message.validate(message)
    end

    test "rejects messages with invalid jsonrpc version" do
      message = %{"jsonrpc" => "1.0", "result" => %{}, "id" => "req_123"}
      assert {:error, error} = Message.validate(message)
      assert error.reason == :invalid_request
    end

    test "rejects messages without jsonrpc field" do
      message = %{"result" => %{}, "id" => "req_123"}
      assert {:error, error} = Message.validate(message)
      assert error.reason == :invalid_request
    end

    test "rejects requests with unknown methods" do
      message = %{"jsonrpc" => "2.0", "method" => "unknown", "params" => %{}, "id" => "req_123"}
      assert {:error, error} = Message.validate(message)
      assert error.reason == :method_not_found
    end

    test "rejects notifications with unknown methods" do
      message = %{"jsonrpc" => "2.0", "method" => "unknown", "params" => %{}}
      assert {:error, error} = Message.validate(message)
      assert error.reason == :method_not_found
    end

    test "rejects requests with invalid id types" do
      message = %{"jsonrpc" => "2.0", "method" => "ping", "params" => %{}, "id" => %{}}
      assert {:error, error} = Message.validate(message)
      assert error.reason == :invalid_request
    end
  end

  describe "to_domain/1" do
    test "converts response messages to Response structs" do
      message = %{"jsonrpc" => "2.0", "result" => %{"data" => "value"}, "id" => "req_123"}

      assert {:ok, response} = Message.to_domain(message)
      assert %Response{} = response
      assert response.result == %{"data" => "value"}
      assert response.id == "req_123"
      assert response.is_error == false
    end

    test "detects domain errors in responses" do
      message = %{
        "jsonrpc" => "2.0",
        "result" => %{"isError" => true, "reason" => "not_found"},
        "id" => "req_123"
      }

      assert {:ok, response} = Message.to_domain(message)
      assert %Response{} = response
      assert response.is_error == true
    end

    test "converts error messages to Error structs" do
      message = %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => -32_700, "message" => "Parse error"},
        "id" => "req_123"
      }

      assert {:ok, error} = Message.to_domain(message)
      assert %Error{} = error
      assert error.code == -32_700
      assert error.reason == :parse_error
    end

    test "returns error for non-response/error messages" do
      # Request message
      message = %{"jsonrpc" => "2.0", "method" => "ping", "params" => %{}, "id" => "req_123"}

      assert {:error, error} = Message.to_domain(message)
      assert error.reason == :invalid_request
    end
  end
end
