defmodule Hermes.Server.Component.Resource do
  @moduledoc """
  Defines the behaviour for MCP resources.

  Resources represent data that can be read by the client, such as files,
  documents, or any other content. Each resource is identified by a URI
  and can provide content in various formats.

  ## Example

      defmodule MyServer.Resources.Documentation do
        @behaviour Hermes.Server.Behaviour.Resource
        
        alias Hermes.Server.Frame
        
        @impl true
        def uri, do: "file:///docs/readme.md"
        
        @impl true
        def name, do: "Project README"
        
        @impl true
        def description, do: "The main documentation for this project"
        
        @impl true
        def mime_type, do: "text/markdown"
        
        @impl true
        def read(_params, frame) do
          case File.read("README.md") do
            {:ok, content} -> 
              # Can track access in frame
              new_frame = Frame.assign(frame, :last_resource_access, DateTime.utc_now())
              {:ok, content, new_frame}
              
            {:error, reason} -> 
              {:error, "Failed to read README: \#{inspect(reason)}"}
          end
        end
      end

  ## Example with dynamic content

      defmodule MyServer.Resources.SystemStatus do
        @behaviour Hermes.Server.Behaviour.Resource
        
        @impl true
        def uri, do: "system://status"
        
        @impl true
        def name, do: "System Status"
        
        @impl true
        def description, do: "Current system status and metrics"
        
        @impl true
        def mime_type, do: "application/json"
        
        @impl true
        def read(_params, frame) do
          status = %{
            uptime: System.uptime(),
            memory: :erlang.memory(),
            user_id: frame.assigns[:user_id],
            timestamp: DateTime.utc_now()
          }
          
          {:ok, Jason.encode!(status), frame}
        end
      end
  """

  alias Hermes.Server.Frame

  @type params :: map()
  @type content :: binary() | String.t()

  @doc """
  Returns the URI that identifies this resource.

  The URI should be unique within the server and follow standard URI conventions.
  Common schemes include:
  - `file://` for file-based resources
  - `http://` or `https://` for web resources
  - Custom schemes for application-specific resources
  """
  @callback uri() :: String.t()

  @doc """
  Returns the MIME type of the resource content.

  Common MIME types:
  - `text/plain` for plain text
  - `text/markdown` for Markdown
  - `application/json` for JSON data
  - `text/html` for HTML
  - `application/octet-stream` for binary data
  """
  @callback mime_type() :: String.t()

  @doc """
  Reads the resource content.

  ## Parameters

  - `params` - Optional parameters from the client (typically empty for resources)
  - `frame` - The server frame containing context and state

  ## Return Values

  - `{:ok, content}` - Resource read successfully, frame unchanged
  - `{:ok, content, new_frame}` - Resource read successfully with frame updates
  - `{:error, reason}` - Failed to read resource

  ## Content Types

  The content should match the declared MIME type:
  - For text types, return a String
  - For binary types, return binary data
  - For JSON, return the JSON-encoded string
  """
  @callback read(params :: params(), frame :: Frame.t()) ::
              {:ok, content :: content(), new_frame :: Frame.t()}
              | {:error, reason :: String.t()}

  @doc """
  Converts a resource module into the MCP protocol format.
  """
  @spec to_protocol(module()) :: map()
  def to_protocol(resource_module) do
    %{
      "uri" => resource_module.uri(),
      "name" => resource_module.name(),
      "description" => resource_module.description(),
      "mimeType" => resource_module.mime_type()
    }
  end

  @doc """
  Validates that a module implements the Resource behaviour.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    behaviours =
      :attributes
      |> module.__info__()
      |> Keyword.get(:behaviour, [])
      |> List.flatten()

    __MODULE__ in behaviours
  end
end
