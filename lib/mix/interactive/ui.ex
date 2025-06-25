defmodule Mix.Interactive.UI do
  @moduledoc false

  alias Hermes.MCP.Error
  alias IO.ANSI

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
    │       #{String.pad_trailing(title, 34)}│
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
    "#{reason} #{inspect(data, pretty: true)}"
  end

  defp format_error_message(other) do
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

      cond do
        title == "tools" && Map.has_key?(item, "inputSchema") ->
          print_schema(item["inputSchema"])

        title == "prompts" && Map.has_key?(item, "arguments") ->
          print_prompt_arguments(item["arguments"])

        title == "resources" ->
          print_resource_details(item)

        true ->
          nil
      end
    end)

    IO.puts("")
  end

  def print_items(title, items, _key_field) do
    IO.puts("#{@colors.success}Found #{length(items)} #{title}#{@colors.reset}")

    IO.puts("")
  end

  defp print_schema(schema) when is_map(schema) do
    if schema["type"] == "object" && Map.has_key?(schema, "properties") do
      IO.puts("    #{@colors.info}Arguments:#{@colors.reset}")
      print_properties(schema["properties"], Map.get(schema, "required", []))
    end
  end

  defp print_schema(_), do: nil

  defp print_properties(properties, required) when is_map(properties) do
    Enum.each(properties, fn {prop_name, prop_schema} ->
      print_property(prop_name, prop_schema, prop_name in required)
    end)
  end

  defp print_property(name, schema, required) do
    req_marker = if required, do: " (required)", else: ""
    type = Map.get(schema, "type", "any")
    description = Map.get(schema, "description", "")

    IO.puts("      #{@colors.command}#{name}#{@colors.reset}#{req_marker}: #{type}")
    if description != "", do: IO.puts("        #{description}")
  end

  defp print_prompt_arguments(arguments) when is_list(arguments) do
    IO.puts("    #{@colors.info}Arguments:#{@colors.reset}")

    Enum.each(arguments, fn arg ->
      req_marker = if Map.get(arg, "required", false), do: " (required)", else: ""
      name = Map.get(arg, "name", "")
      description = Map.get(arg, "description", "")

      IO.puts("      #{@colors.command}#{name}#{@colors.reset}#{req_marker}")
      if description != "", do: IO.puts("        #{description}")
    end)
  end

  defp print_prompt_arguments(_), do: nil

  defp print_resource_details(resource) when is_map(resource) do
    if Map.has_key?(resource, "mimeType") do
      IO.puts("    #{@colors.info}Type:#{@colors.reset} #{resource["mimeType"]}")
    end

    if Map.has_key?(resource, "name") && resource["name"] != resource["uri"] do
      IO.puts("    #{@colors.info}Name:#{@colors.reset} #{resource["name"]}")
    end
  end
end
