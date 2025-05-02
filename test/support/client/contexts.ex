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
  def setup_initialized_client(_context) do
    expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

    client =
      start_supervised!(
        {Hermes.Client,
         transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
         client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
        restart: :temporary
      )

    allow(Hermes.MockTransport, self(), client)

    initialize_client(client)

    assert request_id = get_request_id(client, "initialize")

    init_response = init_response(request_id)
    send_response(client, init_response)

    Process.sleep(50)

    %{client: client}
  end

  @doc """
  Setup for initializing a client with custom capabilities

  Returns:
  - client: initialized client process with the specified capabilities
  """
  def setup_client_with_capabilities(_context, capabilities) do
    expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

    client =
      start_supervised!(
        {Hermes.Client,
         transport: [layer: Hermes.MockTransport, name: Hermes.MockTransportImpl],
         client_info: %{"name" => "TestClient", "version" => "1.0.0"}},
        restart: :temporary
      )

    allow(Hermes.MockTransport, self(), client)

    initialize_client(client)

    assert request_id = get_request_id(client, "initialize")

    init_response = init_response(request_id, capabilities)
    send_response(client, init_response)

    Process.sleep(50)

    %{client: client}
  end

  @doc """
  Setup for initializing a client with limited capabilities

  Returns:
  - client: initialized client without resources, tools or prompts capabilities
  """
  def setup_client_with_limited_capabilities(context) do
    limited_capabilities = %{"completion" => %{"complete" => true}}
    setup_client_with_capabilities(context, limited_capabilities)
  end

  @doc """
  Setup for initializing a client with custom client info and transport

  This is useful for more complex test scenarios needing specific configuration.
  """
  def setup_custom_client(_context, client_info, transport_opts) do
    expect(Hermes.MockTransport, :send_message, 2, fn _, _message -> :ok end)

    client =
      start_supervised!(
        {Hermes.Client, transport: transport_opts, client_info: client_info},
        restart: :temporary
      )

    allow(Hermes.MockTransport, self(), client)

    initialize_client(client)

    %{client: client, client_info: client_info}
  end
end
