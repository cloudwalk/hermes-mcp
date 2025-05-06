defmodule Hermes.Client.Contexts do
  @moduledoc """
  Common setup contexts for client tests.

  This module provides reusable setup functions for initializing clients with different
  configurations and capabilities.
  """

  import ExUnit.Assertions, only: [assert: 1]
  import ExUnit.Callbacks, only: [start_supervised!: 2]
  import Hermes.Client.Setup
  import Mox

  @doc """
  Setup for initializing a client with default capabilities

  Returns:
  - client: initialized client process
  """
  def initialized_client(ctx) do
    expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

    transport =
      if opts = ctx[:transport],
        do: opts,
        else: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl]

    client_info =
      if info = ctx[:client_info], do: info, else: %{"name" => "TestClient", "version" => "1.0.0"}

    client =
      start_supervised!(
        {Hermes.Client, transport: transport, client_info: client_info, capabilities: ctx[:client_capabilities]},
        restart: :temporary
      )

    allow(Hermes.MockTransport, self(), client)

    initialize_client(client)

    assert request_id = get_request_id(client, "initialize")

    init_response =
      if capabilities = ctx[:server_capabilities],
        do: init_response(request_id, capabilities),
        else: init_response(request_id)

    send_response(client, init_response)

    Map.put(ctx, :client, client)
  end
end
