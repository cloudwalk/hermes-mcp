defmodule Hermes.MessageTest do
  use ExUnit.Case, async: true

  alias Hermes.Message
  require Hermes.Message

  describe "decode/1" do
    test "decodes a single valid message" do
      json = ~s({"jsonrpc":"2.0","method":"ping","id":1}\n)

      assert {:ok, [decoded]} = Message.decode(json)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "ping"
      assert decoded["id"] == 1
    end

    test "decodes multiple messages" do
      json =
        ~s({"jsonrpc":"2.0","method":"ping","id":1}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n)

      assert {:ok, [msg1, msg2]} = Message.decode(json)
      assert msg1["method"] == "ping"
      assert msg2["method"] == "notifications/initialized"
    end

    test "returns error for invalid JSON" do
      json = ~s({"jsonrpc":"2.0","method":broken}\n)

      assert {:error, _} = Message.decode(json)
    end

    test "returns error for non-compliant message" do
      json = ~s({"method":"unknown_method","id":1}\n)

      assert {:error, :invalid_message} = Message.decode(json)
    end
  end

  describe "validate_message/1" do
    test "validates initialize request" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1,
        "params" => %{
          "protocolVersion" => "2024-05-01",
          "capabilities" => %{"foo" => "bar"},
          "clientInfo" => %{
            "name" => "TestClient",
            "version" => "1.0.0"
          }
        }
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates ping request" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "ping",
        "id" => 1
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates resources/list request" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "resources/list",
        "id" => 1,
        "params" => %{
          "cursor" => "next-page"
        }
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates resources/read request" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "resources/read",
        "id" => 1,
        "params" => %{
          "uri" => "file:///path/to/file.txt"
        }
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates notification message" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized"
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates cancelled notification" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/cancelled",
        "params" => %{
          "requestId" => 123,
          "reason" => "User cancelled"
        }
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates response message" do
      msg = %{
        "jsonrpc" => "2.0",
        "result" => %{"status" => "success"},
        "id" => 1
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates pong response message" do
      msg = %{
        "jsonrpc" => "2.0",
        "result" => %{},
        "id" => 1
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "validates error message" do
      msg = %{
        "jsonrpc" => "2.0",
        "error" => %{
          "code" => -32_600,
          "message" => "Invalid Request"
        },
        "id" => 1
      }

      assert {:ok, _} = Message.validate_message(msg)
    end

    test "rejects message with invalid method" do
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "unknown_method",
        "id" => 1
      }

      assert {:error, :invalid_message} = Message.validate_message(msg)
    end

    test "rejects message with missing required fields" do
      # Missing protocolVersion in initialize params
      msg = %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1,
        "params" => %{
          "clientInfo" => %{
            "name" => "TestClient",
            "version" => "1.0.0"
          }
        }
      }

      assert {:error, :invalid_message} = Message.validate_message(msg)
    end
  end

  describe "encode_request/2" do
    test "encodes initialize request" do
      req = %{
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2024-05-01",
          "capabilities" => %{"foo" => "bar"},
          "clientInfo" => %{
            "name" => "TestClient",
            "version" => "1.0.0"
          }
        }
      }

      assert {:ok, encoded} = Message.encode_request(req, 1)
      assert is_binary(encoded)
      assert String.ends_with?(encoded, "\n")

      # Decode to validate
      {:ok, [decoded]} = Message.decode(encoded)
      assert decoded["id"] == 1
      assert decoded["method"] == "initialize"
    end

    test "encodes ping request" do
      req = %{"method" => "ping"}

      assert {:ok, encoded} = Message.encode_request(req, "req-123")
      assert is_binary(encoded)

      # Decode to validate
      {:ok, [decoded]} = Message.decode(encoded)
      assert decoded["id"] == "req-123"
      assert decoded["method"] == "ping"
    end

    test "returns error for invalid request" do
      req = %{"method" => "unknown_method"}

      assert {:error, _} = Message.encode_request(req, 1)
    end
  end

  describe "encode_notification/1" do
    test "encodes initialize notification" do
      notif = %{"method" => "notifications/initialized"}

      assert {:ok, encoded} = Message.encode_notification(notif)
      assert is_binary(encoded)
      assert String.ends_with?(encoded, "\n")

      # Decode to validate
      {:ok, [decoded]} = Message.decode(encoded)
      assert decoded["method"] == "notifications/initialized"
      refute Map.has_key?(decoded, "id")
    end

    test "encodes cancelled notification" do
      notif = %{
        "method" => "notifications/cancelled",
        "params" => %{
          "requestId" => 123,
          "reason" => "User cancelled"
        }
      }

      assert {:ok, encoded} = Message.encode_notification(notif)
      assert is_binary(encoded)

      # Decode to validate
      {:ok, [decoded]} = Message.decode(encoded)
      assert decoded["method"] == "notifications/cancelled"
      assert decoded["params"]["requestId"] == 123
    end

    test "returns error for invalid notification" do
      notif = %{"method" => "unknown_method"}

      assert {:error, _} = Message.encode_notification(notif)
    end
  end

  describe "guards" do
    test "is_request/1 correctly identifies request messages" do
      request = %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1}
      not_request = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

      assert Message.is_request(request)
      refute Message.is_request(not_request)
    end

    test "is_notification/1 correctly identifies notification messages" do
      notification = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
      not_notification = %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1}

      assert Message.is_notification(notification)
      refute Message.is_notification(not_notification)
    end

    test "is_response/1 correctly identifies response messages" do
      response = %{"jsonrpc" => "2.0", "result" => %{}, "id" => 1}
      not_response = %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1}

      assert Message.is_response(response)
      refute Message.is_response(not_response)
    end

    test "is_error/1 correctly identifies error messages" do
      error = %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => -32_600, "message" => "Invalid Request"},
        "id" => 1
      }

      not_error = %{"jsonrpc" => "2.0", "result" => %{}, "id" => 1}

      assert Message.is_error(error)
      refute Message.is_error(not_error)
    end
  end
end
