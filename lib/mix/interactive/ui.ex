defmodule Mix.Interactive.UI do
  @moduledoc """
  Common UI elements and formatting functions for interactive MCP shells.
  """

  alias IO.ANSI

  # Color definitions for better UI
  @colors %{
    prompt: ANSI.bright() <> ANSI.cyan(),
    command: ANSI.green(),
    error: ANSI.red(),
    success: ANSI.bright() <> ANSI.green(),
    info: ANSI.yellow(),
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
    IO.puts("#{@colors.error}Error: #{inspect(reason)}#{@colors.reset}")
  end

  @doc """
  Formats lists of tools/prompts/resources with helpful styling.
  """
  def print_items(title, items, key_field) do
    IO.puts("#{@colors.success}Found #{length(items)} #{title}#{@colors.reset}")
    
    if is_list(items) and length(items) > 0 do
      IO.puts("\n#{@colors.info}Available #{title}:#{@colors.reset}")
      
      Enum.each(items, fn item ->
        IO.puts("  #{@colors.command}#{item[key_field]}#{@colors.reset}")
        if Map.has_key?(item, "description"), do: IO.puts("    #{item["description"]}")
      end)
    end
    
    IO.puts("")
  end
end