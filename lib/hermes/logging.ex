defmodule Hermes.Logging do
  @moduledoc """
  Centralized logging for Hermes MCP client.

  This module provides structured logging functions that automatically manage context
  and format logs appropriately based on log levels.
  """

  require Logger

  @doc """
  Log protocol messages with automatic formatting and context.

  ## Parameters
    * direction - "incoming" or "outgoing"
    * type - message type (e.g., "request", "response", "notification", "error")
    * id - message ID (can be nil)
    * data - the message content
    * metadata - additional metadata to include with level option (:debug, :info, :warning, :error, etc.)
  """
  def message(direction, type, id, data, metadata \\ []) do
    summary = create_message_summary(type, id, data)
    level = Keyword.get(metadata, :level, :debug)
    metadata = Keyword.delete(metadata, :level)

    log(level, "[MCP message] #{direction} #{type}: #{summary}", metadata)

    if should_log_details?(data) do
      log(level, "[MCP message] #{direction} #{type} data: #{inspect(data)}", metadata)
    else
      log(level, "[MCP message] #{direction} #{type} data (truncated): #{truncate_data(data)}", metadata)
    end
  end

  @doc """
  Log server events with structured format.

  ## Options
    * metadata - Additional metadata including:
      * :level - The log level (:debug, :info, :warning, :error, etc.)
  """
  def server_event(event, details, metadata \\ []) do
    level = Keyword.get(metadata, :level, :info)
    metadata = Keyword.delete(metadata, :level)

    log(level, "MCP server event: #{event}", metadata)

    if details do
      log(level, "MCP event details: #{inspect(details)}", metadata)
    end
  end

  @doc """
  Log client events with structured format.

  ## Options
    * metadata - Additional metadata including:
      * :level - The log level (:debug, :info, :warning, :error, etc.)
  """
  def client_event(event, details, metadata \\ []) do
    level = Keyword.get(metadata, :level, :info)
    metadata = Keyword.delete(metadata, :level)

    log(level, "MCP client event: #{event}", metadata)

    if details do
      log(level, "MCP event details: #{inspect(details)}", metadata)
    end
  end

  @doc """
  Log transport events with structured format.

  ## Options
    * metadata - Additional metadata including:
      * :level - The log level (:debug, :info, :warning, :error, etc.)
  """
  def transport_event(event, details, metadata \\ []) do
    level = Keyword.get(metadata, :level, :debug)
    metadata = Keyword.delete(metadata, :level)

    log(level, "MCP transport event: #{event}", metadata)

    if details do
      log(level, "MCP transport details: #{inspect(details)}", metadata)
    end
  end

  @doc """
  Set context for all subsequent logs in the current process.
  """
  def context(metadata) when is_list(metadata) do
    Logger.metadata(metadata)
  end

  @doc """
  Add context to existing metadata for all subsequent logs.
  """
  def add_context(metadata) when is_list(metadata) do
    Logger.metadata(Keyword.merge(Logger.metadata(), metadata))
  end

  # Private helpers

  # Route log messages to the appropriate Logger function based on level
  defp log(level, message, metadata) when is_atom(level) do
    log_by_level(level, message, metadata)
  end

  # Map MCP log levels to Elixir logger levels
  defp log_by_level(:debug, message, metadata), do: Logger.debug(message, metadata)
  defp log_by_level(:info, message, metadata), do: Logger.info(message, metadata)
  defp log_by_level(:notice, message, metadata), do: Logger.info(message, metadata)
  defp log_by_level(:warning, message, metadata), do: Logger.warning(message, metadata)
  defp log_by_level(:error, message, metadata), do: Logger.error(message, metadata)
  defp log_by_level(:critical, message, metadata), do: Logger.error(message, metadata)
  defp log_by_level(:alert, message, metadata), do: Logger.error(message, metadata)
  defp log_by_level(:emergency, message, metadata), do: Logger.error(message, metadata)
  defp log_by_level(_, message, metadata), do: Logger.info(message, metadata)

  defp create_message_summary("request", id, data) when is_map(data) do
    method = Map.get(data, "method", "unknown")
    "id=#{id || "none"} method=#{method}"
  end

  defp create_message_summary("response", id, data) when is_map(data) do
    result_summary =
      cond do
        Map.has_key?(data, "result") -> "success"
        Map.has_key?(data, "error") -> "error: #{get_in(data, ["error", "code"])}"
        true -> "unknown"
      end

    "id=#{id || "none"} #{result_summary}"
  end

  defp create_message_summary("notification", _id, data) when is_map(data) do
    method = Map.get(data, "method", "unknown")
    "method=#{method}"
  end

  defp create_message_summary(_type, id, _data) do
    "id=#{id || "none"}"
  end

  defp should_log_details?(data) when is_binary(data), do: byte_size(data) < 500
  defp should_log_details?(data) when is_map(data), do: map_size(data) < 10
  defp should_log_details?(_), do: true

  defp truncate_data(data) when is_binary(data), do: "#{String.slice(data, 0, 100)}..."

  defp truncate_data(data) when is_map(data) do
    important_keys =
      case data do
        %{"id" => _, "method" => _} -> ["id", "method"]
        %{"id" => _, "result" => _} -> ["id"]
        %{"id" => _, "error" => _} -> ["id", "error"]
        %{"method" => _} -> ["method"]
        _ -> Enum.take(Map.keys(data), 3)
      end

    data
    |> Map.take(important_keys)
    |> inspect()
    |> Kernel.<>("...")
  end

  defp truncate_data(data), do: inspect(data, limit: 5)
end
