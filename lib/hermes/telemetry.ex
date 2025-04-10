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

  @doc """
  Execute a span operation with telemetry events for start, stop, and exception.

  This is a wrapper around `:telemetry.span/3` that adds the Hermes MCP namespace prefix.

  ## Parameters
  - `event_name` - List of atoms for the event name, excluding the :hermes_mcp prefix
  - `metadata` - Map of metadata for the event
  - `function` - Function to execute and measure

  ## Returns
  - The return value of the function
  """
  @spec span(list(atom()), map(), (-> {term(), map()} | term())) :: term()
  def span(event_name, metadata, function) do
    :telemetry.span([:hermes_mcp | event_name], metadata, function)
  end

  @doc """
  Attach a handler to a specific Hermes MCP telemetry event.

  ## Parameters
  - `handler_id` - Unique ID for the handler
  - `event_name` - List of atoms for the event name, excluding the :hermes_mcp prefix
  - `handler` - Function to handle the event
  - `config` - Configuration for the handler

  ## Returns
  - `:ok` if successful
  - `{:error, reason}` if attachment fails
  """
  @spec attach(binary(), list(atom()), function(), term()) :: :ok | {:error, term()}
  def attach(handler_id, event_name, handler, config) do
    :telemetry.attach(handler_id, [:hermes_mcp | event_name], handler, config)
  end

  @doc """
  Attach a handler to multiple Hermes MCP telemetry events.

  ## Parameters
  - `handler_id` - Unique ID for the handler
  - `event_names` - List of event name lists, each excluding the :hermes_mcp prefix
  - `handler` - Function to handle the events
  - `config` - Configuration for the handler

  ## Returns
  - `:ok` if successful
  - `{:error, reason}` if attachment fails
  """
  @spec attach_many(binary(), list(list(atom())), function(), term()) :: :ok | {:error, term()}
  def attach_many(handler_id, event_names, handler, config) do
    prefixed_events = Enum.map(event_names, &[:hermes_mcp | &1])
    :telemetry.attach_many(handler_id, prefixed_events, handler, config)
  end

  @doc """
  Detach a handler from Hermes MCP telemetry events.

  ## Parameters
  - `handler_id` - ID of the handler to detach

  ## Returns
  - `:ok` if successful
  - `{:error, :not_found}` if handler not found
  """
  @spec detach(binary()) :: :ok | {:error, :not_found}
  def detach(handler_id) do
    :telemetry.detach(handler_id)
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

  # Message events
  def event_message_encode, do: [:message, :encode]
  def event_message_decode, do: [:message, :decode]

  # Progress events
  def event_progress_update, do: [:progress, :update]
end
