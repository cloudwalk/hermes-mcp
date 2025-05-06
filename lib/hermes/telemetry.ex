defmodule Hermes.Telemetry do
  @moduledoc """
  Telemetry integration for Hermes MCP.

  This module defines telemetry events emitted by Hermes MCP and provides
  helper functions for emitting events consistently across the codebase.

  ## Event Naming Convention

  All telemetry events emitted by Hermes MCP follow the namespace pattern:
  `[:hermes_mcp, component, action]`

  Where:
  - `:hermes_mcp` is the root namespace
  - `component` is the specific component emitting the event (e.g., `:client`, `:transport`)
  - `action` is the specific action or lifecycle event (e.g., `:init`, `:request`, `:response`)

  ## Span Events

  Many operations in Hermes MCP emit span events using `:telemetry.span/3`, which
  generates three potential events:
  - `[..., :start]` - When the operation begins
  - `[..., :stop]` - When the operation completes successfully
  - `[..., :exception]` - When the operation fails with an exception

  ## Example

  ```elixir
  :telemetry.attach(
    "log-client-requests",
    [:hermes_mcp, :client, :request, :stop],
    fn _event, %{duration: duration}, %{method: method}, _config ->
      Logger.info("Request to \#{method} completed in \#{div(duration, 1_000_000)} ms")
    end,
    nil
  )
  ```
  """

  @doc """
  Execute a telemetry event with the Hermes MCP namespace.

  ## Parameters
  - `event_name` - List of atoms for the event name, excluding the :hermes_mcp prefix
  - `measurements` - Map of measurements for the event
  - `metadata` - Map of metadata for the event
  """
  @spec execute(list(atom()), map(), map()) :: :ok
  def execute(event_name, measurements, metadata) do
    :telemetry.execute([:hermes_mcp | event_name], measurements, metadata)
  end

  # Define event name constants to ensure consistency

  # Client events
  def event_client_init, do: [:client, :init]
  def event_client_request, do: [:client, :request]
  def event_client_response, do: [:client, :response]
  def event_client_terminate, do: [:client, :terminate]
  def event_client_error, do: [:client, :error]

  # Transport events
  def event_transport_init, do: [:transport, :init]
  def event_transport_connect, do: [:transport, :connect]
  def event_transport_send, do: [:transport, :send]
  def event_transport_receive, do: [:transport, :receive]
  def event_transport_disconnect, do: [:transport, :disconnect]
  def event_transport_error, do: [:transport, :error]
  def event_transport_terminate, do: [:transport, :terminate]

  # Message events
  def event_message_encode, do: [:message, :encode]
  def event_message_decode, do: [:message, :decode]

  # Progress events
  def event_progress_update, do: [:progress, :update]

  # Roots events
  def event_client_roots, do: [:client, :roots]
end
