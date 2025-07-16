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

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @type params :: map()
  @type content :: binary() | String.t()

  @type t :: %__MODULE__{
          uri: String.t(),
          name: String.t(),
          description: String.t() | nil,
          mime_type: String.t(),
          handler: module | nil,
          title: String.t() | nil,
          uri_template: String.t() | nil
        }

  defstruct [
    :uri,
    :name,
    description: nil,
    mime_type: "text/plain",
    handler: nil,
    title: nil,
    uri_template: nil
  ]

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
              {:reply, response :: Response.t(), new_state :: Frame.t()}
              | {:noreply, new_state :: Frame.t()}
              | {:error, error :: Error.t(), new_state :: Frame.t()}

  defimpl JSON.Encoder, for: __MODULE__ do
    alias Hermes.Server.Component.Resource

    def encode(%Resource{uri_template: uri_template} = resource, _) when not is_nil(uri_template) do
      %{
        uriTemplate: uri_template,
        name: resource.name
      }
      |> then(&if resource.title, do: Map.put(&1, :title, resource.title), else: &1)
      |> then(&if resource.description, do: Map.put(&1, :description, resource.description), else: &1)
      |> then(&if resource.mime_type, do: Map.put(&1, :mimeType, resource.mime_type), else: &1)
      |> JSON.encode!()
    end

    def encode(%Resource{} = resource, _) do
      resource
      |> Map.take([:name, :uri, :description, :title])
      |> Map.put(:mimeType, resource.mime_type)
      |> JSON.encode!()
    end
  end
end
