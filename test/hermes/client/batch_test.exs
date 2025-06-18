defmodule Hermes.Client.BatchTest do
  use Hermes.MCP.Case, async: true

  import Mox

  alias Hermes.Client.Operation
  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Hermes.MockTransport, MockTransport)
    :ok
  end

  describe "send_batch/2" do
    setup :initialized_client

    test "sends batch of operations and returns results map", %{client: client} do
      operations = [
        Operation.new(%{method: "ping", params: %{}}),
        Operation.new(%{method: "tools/list", params: %{}})
      ]

      expect(Hermes.MockTransport, :send_message, fn _, message ->
        {:ok, decoded} = JSON.decode(message)
        assert is_list(decoded)
        assert length(decoded) == 2

        [ping_msg, tools_msg] = decoded
        assert ping_msg["method"] == "ping"
        assert tools_msg["method"] == "tools/list"
        assert ping_msg["jsonrpc"] == "2.0"
        assert tools_msg["jsonrpc"] == "2.0"
        assert is_binary(ping_msg["id"])
        assert is_binary(tools_msg["id"])

        :ok
      end)

      task = Task.async(fn -> Hermes.Client.Base.send_batch(client, operations) end)
      Process.sleep(50)

      pending_requests = :sys.get_state(client).pending_requests
      request_ids = Map.keys(pending_requests)
      assert length(request_ids) == 2

      batch_response = [
        %{
          "jsonrpc" => "2.0",
          "result" => %{},
          "id" => Enum.at(request_ids, 0)
        },
        %{
          "jsonrpc" => "2.0",
          "result" => %{"tools" => [%{"name" => "test_tool"}]},
          "id" => Enum.at(request_ids, 1)
        }
      ]

      {:ok, encoded_batch} = Message.encode_batch(batch_response)
      GenServer.cast(client, {:response, encoded_batch})

      assert {:ok, results} = Task.await(task)
      assert is_map(results)
      assert map_size(results) == 2

      {ping_result, tools_result} =
        results
        |> Enum.sort_by(fn {id, _} -> id end)
        |> then(fn sorted ->
          {
            elem(Enum.at(sorted, 0), 1),
            elem(Enum.at(sorted, 1), 1)
          }
        end)

      assert {:ok, %Response{}} = ping_result
      assert {:ok, %Response{result: %{"tools" => [%{"name" => "test_tool"}]}}} = tools_result
    end

    test "handles mixed success and error responses in batch", %{client: client} do
      operations = [
        Operation.new(%{method: "ping", params: %{}}),
        Operation.new(%{method: "tools/list", params: %{}})
      ]

      expect(Hermes.MockTransport, :send_message, fn _, _message -> :ok end)

      task = Task.async(fn -> Hermes.Client.Base.send_batch(client, operations) end)
      Process.sleep(50)

      pending_requests = :sys.get_state(client).pending_requests
      request_ids = Map.keys(pending_requests)
      assert length(request_ids) == 2

      batch_response = [
        %{
          "jsonrpc" => "2.0",
          "result" => %{},
          "id" => Enum.at(request_ids, 0)
        },
        %{
          "jsonrpc" => "2.0",
          "error" => %{"code" => -32_601, "message" => "Method not found"},
          "id" => Enum.at(request_ids, 1)
        }
      ]

      {:ok, encoded_batch} = Message.encode_batch(batch_response)
      GenServer.cast(client, {:response, encoded_batch})

      assert {:ok, results} = Task.await(task)
      assert map_size(results) == 2

      results_list = Map.values(results)
      assert Enum.any?(results_list, &match?({:ok, %Response{}}, &1))
      assert Enum.any?(results_list, &match?({:error, %Error{}}, &1))
    end

    test "returns error for empty batch", %{client: client} do
      assert {:error, %Error{reason: :invalid_request}} =
               Hermes.Client.Base.send_batch(client, [])
    end

    test "handles transport send failure", %{client: client} do
      operations = [Operation.new(%{method: "ping", params: %{}})]

      expect(Hermes.MockTransport, :send_message, fn _, _ ->
        {:error, :connection_lost}
      end)

      assert {:error, %Error{reason: :send_failure}} =
               Hermes.Client.Base.send_batch(client, operations)
    end

    test "respects operation timeouts", %{client: client} do
      operations = [
        Operation.new(%{method: "ping", params: %{}, timeout: 100})
      ]

      expect(Hermes.MockTransport, :send_message, 2, fn _, _ -> :ok end)

      task = Task.async(fn -> Hermes.Client.Base.send_batch(client, operations) end)
      Process.sleep(50)
      pending_requests = :sys.get_state(client).pending_requests
      assert map_size(pending_requests) == 1

      Process.sleep(100)

      assert {:ok, %{}} = Task.await(task)
    end

    test "batch requests share the same batch_id", %{client: client} do
      operations = [
        Operation.new(%{method: "ping", params: %{}}),
        Operation.new(%{method: "tools/list", params: %{}})
      ]

      expect(Hermes.MockTransport, :send_message, fn _, _ -> :ok end)

      Task.async(fn -> Hermes.Client.Base.send_batch(client, operations) end)
      Process.sleep(50)

      state = :sys.get_state(client)
      requests = Map.values(state.pending_requests)

      assert length(requests) == 2
      batch_ids = Enum.map(requests, & &1.batch_id)
      assert Enum.all?(batch_ids, &(not is_nil(&1)))
      assert length(Enum.uniq(batch_ids)) == 1
      assert String.starts_with?(hd(batch_ids), "batch_")
    end
  end

  describe "batch response handling" do
    setup :initialized_client

    test "handles batch responses in any order", %{client: client} do
      operations = [
        Operation.new(%{method: "ping", params: %{}}),
        Operation.new(%{method: "tools/list", params: %{}})
      ]

      expect(Hermes.MockTransport, :send_message, fn _, _ -> :ok end)

      task = Task.async(fn -> Hermes.Client.Base.send_batch(client, operations) end)
      Process.sleep(50)

      pending_requests = :sys.get_state(client).pending_requests
      [id1, id2] = pending_requests |> Map.keys() |> Enum.sort()

      batch_response = [
        %{
          "jsonrpc" => "2.0",
          "result" => %{"tools" => []},
          "id" => id2
        },
        %{
          "jsonrpc" => "2.0",
          "result" => %{},
          "id" => id1
        }
      ]

      {:ok, encoded_batch} = Message.encode_batch(batch_response)
      GenServer.cast(client, {:response, encoded_batch})

      assert {:ok, results} = Task.await(task)
      assert Map.has_key?(results, id1)
      assert Map.has_key?(results, id2)
    end

    test "ignores notifications in batch response", %{client: client} do
      operations = [
        Operation.new(%{method: "ping", params: %{}})
      ]

      expect(Hermes.MockTransport, :send_message, fn _, _ -> :ok end)

      task = Task.async(fn -> Hermes.Client.Base.send_batch(client, operations) end)
      Process.sleep(50)

      pending_requests = :sys.get_state(client).pending_requests
      [request_id] = Map.keys(pending_requests)

      batch_response = [
        %{
          "jsonrpc" => "2.0",
          "method" => "notifications/message",
          "params" => %{"level" => "info", "data" => "test"}
        },
        %{
          "jsonrpc" => "2.0",
          "result" => %{},
          "id" => request_id
        }
      ]

      {:ok, encoded_batch} = Message.encode_batch(batch_response)
      GenServer.cast(client, {:response, encoded_batch})

      assert {:ok, results} = Task.await(task)
      assert map_size(results) == 1
      assert Map.has_key?(results, request_id)
    end
  end
end
