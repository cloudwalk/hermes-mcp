defmodule Ascii.MCPServer do
  @moduledoc """
  MCP server that generates ASCII art from text.
  """

  use Hermes.Server,
    name: "ASCII Art Generator",
    version: "1.0.0",
    capabilities: [:tools]

  alias Hermes.MCP.Error
  require Logger

  @impl true
  def handle_request(%{"method" => "tools/list"} = _request, state) do
    response = %{
      "tools" => [
        %{
          "name" => "text_to_ascii",
          "description" => "Convert text to ASCII art using various fonts",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "text" => %{
                "type" => "string",
                "description" => "The text to convert to ASCII art"
              },
              "font" => %{
                "type" => "string",
                "description" => "The font to use (standard, slant, 3d, banner)",
                "enum" => ["standard", "slant", "3d", "banner"],
                "default" => "standard"
              }
            },
            "required" => ["text"]
          }
        },
        %{
          "name" => "list_fonts",
          "description" => "List all available ASCII art fonts",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{}
          }
        },
        %{
          "name" => "generate_banner",
          "description" => "Generate a simple banner with text",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{
              "text" => %{
                "type" => "string",
                "description" => "The text for the banner"
              },
              "width" => %{
                "type" => "integer",
                "description" => "Banner width in characters",
                "minimum" => 20,
                "maximum" => 100,
                "default" => 60
              }
            },
            "required" => ["text"]
          }
        }
      ]
    }

    {:reply, response, state}
  end

  @impl true
  def handle_request(
        %{"method" => "tools/call", "params" => %{"name" => "text_to_ascii", "arguments" => args}} =
          _request,
        state
      ) do
    case Map.get(args, "text") do
      nil ->
        {:error, Error.protocol(:invalid_params, %{message: "Missing required parameter: text"}), state}

      text when is_binary(text) ->
        font = Map.get(args, "font", "standard")

        case Ascii.ArtGenerator.generate(text, font) do
          {:ok, art} ->
            response = %{
              "content" => [
                %{
                  "type" => "text",
                  "text" => art
                }
              ],
              "isError" => false
            }

            # Save to database for history
            {:ok, _} =
              Ascii.ArtHistory.create_art(%{
                text: text,
                font: font,
                result: art
              })

            {:reply, response, state}

          {:error, reason} ->
            {:error, Error.execution("Failed to generate art: #{reason}"), state}
        end

      _ ->
        {:error, Error.protocol(:invalid_params, %{message: "Parameter 'text' must be a string"}), state}
    end
  end

  @impl true
  def handle_request(
        %{"method" => "tools/call", "params" => %{"name" => "list_fonts"}} = _request,
        state
      ) do
    fonts = Ascii.ArtGenerator.list_fonts()

    response = %{
      "content" => [
        %{
          "type" => "text",
          "text" => "Available fonts:\\n#{Enum.join(fonts, "\\n")}"
        }
      ],
      "isError" => false
    }

    {:reply, response, state}
  end

  @impl true
  def handle_request(
        %{
          "method" => "tools/call",
          "params" => %{"name" => "generate_banner", "arguments" => args}
        } = _request,
        state
      ) do
    case Map.get(args, "text") do
      nil ->
        {:error, Error.protocol(:invalid_params, %{message: "Missing required parameter: text"}), state}

      text when is_binary(text) ->
        width = Map.get(args, "width", 60)

        banner = Ascii.ArtGenerator.generate_banner(text, width)

        response = %{
          "content" => [
            %{
              "type" => "text",
              "text" => banner
            }
          ],
          "isError" => false
        }

        {:reply, response, state}

      _ ->
        {:error, Error.protocol(:invalid_params, %{message: "Parameter 'text' must be a string"}), state}
    end
  end

  @impl true
  def handle_request(request, state) do
    {:error, Error.protocol(:method_not_found, %{method: request["method"]}), state}
  end

  @impl true
  def handle_notification(_notification, state) do
    {:noreply, state}
  end
end
