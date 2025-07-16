defmodule Hermes.Logging do
  @moduledoc false

  require Logger

  @doc false
  defmacro __using__(_) do
    quote do
      alias Hermes.Logging

      require Logger
      require Logging
    end
  end

  @doc """
  Log protocol messages with automatic formatting and context.

  ## Parameters
    * direction - "incoming" or "outgoing"
    * type - message type (e.g., "request", "response", "notification", "error")
    * id - message ID (can be nil)
    * data - the message content
    * metadata - additional metadata to include with level option (:debug, :info, :warning, :error, etc.)
  """
  defmacro message(direction, type, id, data, metadata \\ []) do
    quote do
      level = Hermes.Logging.get_logging_level(:protocol_messages)
      level = Keyword.get(unquote(metadata), :level, level)
      metadata = Keyword.delete(unquote(metadata), :level)

      summary =
        Hermes.Logging.create_message_summary(
          unquote(type),
          unquote(id),
          unquote(data)
        )

      Hermes.Logging.log(
        level,
        "[MCP message] #{unquote(direction)} #{unquote(type)}: #{summary}",
        metadata
      )

      if Hermes.Logging.should_log_details?(unquote(data)) do
        Hermes.Logging.log(
          level,
          "[MCP message] #{unquote(direction)} #{unquote(type)} data: #{inspect(unquote(data))}",
          metadata
        )
      else
        Hermes.Logging.log(
          level,
          "[MCP message] #{unquote(direction)} #{unquote(type)} data (truncated): #{Hermes.Logging.truncate_data(unquote(data))}",
          metadata
        )
      end
    end
  end

  @doc """
  Log server events with structured format.

  ## Options
    * metadata - Additional metadata including:
      * :level - The log level (:debug, :info, :warning, :error, etc.)
  """
  defmacro server_event(event, details, metadata \\ []) do
    quote do
      level = Hermes.Logging.get_logging_level(:server_events)
      level = Keyword.get(unquote(metadata), :level, level)
      metadata = Keyword.delete(unquote(metadata), :level)

      Hermes.Logging.log(level, "MCP server event: #{unquote(event)}", metadata)

      if Hermes.Logging.should_log_details?(unquote(details)) do
        Hermes.Logging.log(
          level,
          "MCP event details: #{inspect(unquote(details))}",
          metadata
        )
      end
    end
  end

  @doc """
  Log client events with structured format.

  ## Options
    * metadata - Additional metadata including:
      * :level - The log level (:debug, :info, :warning, :error, etc.)
  """
  defmacro client_event(event, details, metadata \\ []) do
    quote do
      level = Hermes.Logging.get_logging_level(:client_events)
      level = Keyword.get(unquote(metadata), :level, level)
      metadata = Keyword.delete(unquote(metadata), :level)

      Hermes.Logging.log(level, "MCP client event: #{unquote(event)}", metadata)

      if Hermes.Logging.should_log_details?(unquote(details)) do
        Hermes.Logging.log(
          level,
          "MCP event details: #{inspect(unquote(details))}",
          metadata
        )
      end
    end
  end

  @doc """
  Log transport events with structured format.

  ## Options
    * metadata - Additional metadata including:
      * :level - The log level (:debug, :info, :warning, :error, etc.)
  """
  defmacro transport_event(event, details, metadata \\ []) do
    quote do
      level = Hermes.Logging.get_logging_level(:transport_events)
      level = Keyword.get(unquote(metadata), :level, level)
      metadata = Keyword.delete(unquote(metadata), :level)

      Hermes.Logging.log(level, "MCP transport event: #{unquote(event)}", metadata)

      if Hermes.Logging.should_log_details?(unquote(details)) do
        Hermes.Logging.log(
          level,
          "MCP transport details: #{inspect(unquote(details))}",
          metadata
        )
      end
    end
  end

  # Private helpers

  @doc false
  def log(level, message, metadata) when is_atom(level) do
    if should_log?(level), do: log_by_level(level, message, metadata)
  end

  defp should_log?(level) do
    log? = Application.get_env(:hermes_mcp, :log, true)
    config_level = Application.get_env(:logger, :level, :debug)
    log? and Logger.compare_levels(config_level, level) != :lt
  end

  @doc false
  def get_logging_level(event_type) do
    logging_config = Application.get_env(:hermes_mcp, :logging, [])
    Keyword.get(logging_config, event_type, :debug)
  end

  defp log_by_level(:debug, msg, metadata), do: Logger.debug(msg, metadata)
  defp log_by_level(:info, msg, metadata), do: Logger.info(msg, metadata)
  defp log_by_level(:notice, msg, metadata), do: Logger.notice(msg, metadata)
  defp log_by_level(:warning, msg, metadata), do: Logger.warning(msg, metadata)
  defp log_by_level(:error, msg, metadata), do: Logger.error(msg, metadata)
  defp log_by_level(:critical, msg, metadata), do: Logger.critical(msg, metadata)
  defp log_by_level(:alert, msg, metadata), do: Logger.alert(msg, metadata)
  defp log_by_level(:emergency, msg, metadata), do: Logger.emergency(msg, metadata)
  defp log_by_level(_, msg, metadata), do: Logger.info(msg, metadata)

  @doc false
  def create_message_summary("request", id, data) when is_map(data) do
    method = Map.get(data, "method", "unknown")
    "id=#{id || "none"} method=#{method}"
  end

  def create_message_summary("response", id, data) when is_map(data) do
    result_summary =
      cond do
        Map.has_key?(data, "result") -> "success"
        Map.has_key?(data, "error") -> "error: #{get_in(data, ["error", "code"])}"
        true -> "unknown"
      end

    "id=#{id || "none"} #{result_summary}"
  end

  def create_message_summary("notification", _id, data) when is_map(data) do
    method = Map.get(data, "method", "unknown")
    "method=#{method}"
  end

  def create_message_summary(_type, id, _data) do
    "id=#{id || "none"}"
  end

  @doc false
  def should_log_details?(data) when is_binary(data), do: byte_size(data) < 500
  def should_log_details?(data) when is_map(data), do: map_size(data) < 10
  def should_log_details?(nil), do: false
  def should_log_details?(_), do: true

  @doc false
  def truncate_data(data) when is_binary(data), do: "#{String.slice(data, 0, 100)}..."

  def truncate_data(data) when is_map(data) do
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

  def truncate_data(data), do: inspect(data, limit: 5)
end
