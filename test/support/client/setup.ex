defmodule Hermes.Client.Setup do
  @moduledoc false

  alias Hermes.Client.State
  alias Hermes.MCP.Message

  @default_server_capabilities %{
    "resources" => %{},
    "tools" => %{},
    "prompts" => %{},
    "logging" => %{},
    "completion" => %{"complete" => true}
  }

  @default_server_info %{
    "name" => "TestServer",
    "version" => "1.0.0"
  }

  @doc """
  Initializes a client for testing by sending the initialize message
  """
  def initialize_client(client) do
    GenServer.cast(client, :initialize)
  end

  @doc """
  Creates a standard server init response
  """
  def init_response(request_id, capabilities \\ @default_server_capabilities) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "capabilities" => capabilities,
        "serverInfo" => @default_server_info,
        "protocolVersion" => "2024-11-05"
      }
    }
  end

  @doc """
  Sends a response to the client (encodes and casts)
  """
  def send_response(client, response) do
    {:ok, encoded} = Message.encode_response(response, response["id"])
    GenServer.cast(client, {:response, encoded})
  end

  @doc """
  Sends a notification to the client (encodes and casts)
  """
  def send_notification(client, notification) do
    {:ok, encoded} = Message.encode_notification(notification)
    GenServer.cast(client, {:response, encoded})
  end

  @doc """
  Sends an error to the client (encodes and casts)
  """
  def send_error(client, error) do
    {:ok, encoded} = Message.encode_error(error, error["id"])
    GenServer.cast(client, {:response, encoded})
  end

  @doc """
  Helper function to get request_id from state for a specific method
  """
  def get_request_id(client, expected_method) do
    state = :sys.get_state(client)
    pending_requests = State.list_pending_requests(state)

    Enum.find_value(pending_requests, nil, fn
      %{method: ^expected_method, id: id} -> id
      _ -> nil
    end)
  end
end
