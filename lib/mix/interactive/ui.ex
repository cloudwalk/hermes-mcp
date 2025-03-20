defmodule Mix.Interactive.UI do
  @moduledoc """
  Common UI elements and formatting functions for interactive MCP shells.

  This module provides consistent UI components and formatting helpers for
  the interactive CLI interfaces used by the Hermes MCP mix tasks.

  It includes functions for displaying colored text, formatted headers,
  pretty-printing of data structures, and consistent output formatting.
  """

  alias Hermes.MCP.Error
  alias IO.ANSI

  # Color definitions for better UI
  @colors %{
    prompt: ANSI.bright() <> ANSI.cyan(),
    command: ANSI.green(),
    error: ANSI.red(),
    success: ANSI.bright() <> ANSI.green(),
    info: ANSI.yellow(),
    warning: ANSI.bright() <> ANSI.yellow(),
    reset: ANSI.reset()
  }

  @doc """
  Returns the color configuration map for styling output.
  """
  def colors, do: @colors

  @doc """
  Creates a styled header for an interactive session.
  """
  def header(title) do
    """
    #{ANSI.bright()}#{ANSI.cyan()}
    ┌─────────────────────────────────────────┐
    │       #{String.pad_trailing(title, 35)}│
    └─────────────────────────────────────────┘
    #{ANSI.reset()}
    """
  end

  @doc """
  Formats JSON or other data for pretty-printing with indentation.
  """
  def format_output(data) do
    data
    |> JSON.encode!()
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> "  " <> line end)
  rescue
    _ -> "  " <> inspect(data, pretty: true, width: 80)
  end

  @doc """
  Formats error messages with appropriate styling.
  """
  def print_error(reason) do
    message = format_error_message(reason)
    IO.puts("#{@colors.error}Error: #{message}#{@colors.reset}")
  end

  defp format_error_message(%Error{reason: :server_capabilities_not_set}) do
    "Server capabilities not available. Connection may not be established."
  end

  defp format_error_message(%Error{reason: :connection_refused}) do
    "Connection refused. Server may be unavailable."
  end

  defp format_error_message(%Error{reason: :request_timeout}) do
    "Request timed out. Server may be busy or unreachable."
  end

  defp format_error_message(%Error{reason: reason, data: data}) do
    # For any other MCP error, format in a user-friendly way
    "#{reason} #{inspect(data, pretty: true)}"
  end

  defp format_error_message(other) do
    # For anything else, just use inspect
    inspect(other, pretty: true)
  end

  @doc """
  Formats lists of tools/prompts/resources with helpful styling.
  """
  def print_items(title, [_ | _] = items, key_field) do
    IO.puts("#{@colors.success}Found #{length(items)} #{title}#{@colors.reset}")

    IO.puts("\n#{@colors.info}Available #{title}:#{@colors.reset}")

    Enum.each(items, fn item ->
      IO.puts("  #{@colors.command}#{item[key_field]}#{@colors.reset}")
      if Map.has_key?(item, "description"), do: IO.puts("    #{item["description"]}")
    end)

    IO.puts("")
  end

  def print_items(title, items, _key_field) do
    IO.puts("#{@colors.success}Found #{length(items)} #{title}#{@colors.reset}")

    IO.puts("")
  end
end
