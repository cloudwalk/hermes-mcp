defmodule Hermes.Telemetry do
  @moduledoc false

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
  def event_client_notification, do: [:client, :notification]

  # Server events
  def event_server_init, do: [:server, :init]
  def event_server_request, do: [:server, :request]
  def event_server_response, do: [:server, :response]
  def event_server_notification, do: [:server, :notification]
  def event_server_error, do: [:server, :error]
  def event_server_terminate, do: [:server, :terminate]
  def event_server_tool_call, do: [:server, :tool_call]
  def event_server_resource_read, do: [:server, :resource_read]
  def event_server_prompt_get, do: [:server, :prompt_get]

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

  # Session events (for StreamableHTTP transport)
  def event_server_session_created, do: [:server, :session, :created]
  def event_server_session_terminated, do: [:server, :session, :terminated]
  def event_server_session_cleanup, do: [:server, :session, :cleanup]
end
