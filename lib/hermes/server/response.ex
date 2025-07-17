defmodule Hermes.Server.Response do
  @moduledoc """
  Fluent interface for building MCP component responses.

  This module provides builders for tool, prompt, and resource responses
  that integrate seamlessly with the component system.

  ## Examples

      # Tool response
      Response.tool()
      |> Response.text("Result: " <> result)
      |> Response.build()
      
      # Resource response (uri and mime_type come from component)
      Response.resource()
      |> Response.text(file_contents)
      |> Response.build()
      
      # Prompt response
      Response.prompt()
      |> Response.user_message("What is the weather?")
      |> Response.assistant_message("Let me check...")
      |> Response.build()
  """

  @type t :: %__MODULE__{
          type: :tool | :prompt | :resource | :completion,
          content: list(map),
          messages: list(map),
          contents: map | nil,
          values: list(map),
          total: integer | nil,
          hasMore: boolean,
          isError: boolean,
          structured_content: map | nil,
          metadata: map
        }

  @type annotations ::
          Enumerable.t(
            {:last_modified, DateTime.t() | nil}
            | {:audience, list(:user | :assistant) | nil}
            | {:priority, float | nil}
          )

  defstruct [
    :type,
    content: [],
    messages: [],
    contents: nil,
    values: [],
    total: nil,
    hasMore: false,
    isError: false,
    structured_content: nil,
    metadata: %{}
  ]

  @doc """
  Start building a tool response.

  ## Examples

      iex> Response.tool()
      %Response{type: :tool, content: [], isError: false}
  """
  @spec tool :: t()
  def tool, do: %__MODULE__{type: :tool}

  @doc """
  Start building a prompt response with optional description.

  ## Parameters

    * `description` - Optional description of the prompt

  ## Examples

      iex> Response.prompt()
      %Response{type: :prompt, messages: []}
      
      iex> Response.prompt("Weather assistant prompt")
      %Response{type: :prompt, messages: [], description: "Weather assistant prompt"}
  """
  @spec prompt :: t()
  @spec prompt(description :: String.t() | nil) :: t()
  def prompt(description \\ nil) do
    response = %__MODULE__{type: :prompt}
    if description, do: Map.put(response, :description, description), else: response
  end

  @doc """
  Start building a resource response.

  The uri and mimeType are automatically injected from the component's
  uri/0 and mime_type/0 callbacks when the response is built by the server.

  ## Examples

      iex> Response.resource()
      %Response{type: :resource, contents: nil}
  """
  @spec resource :: t()
  def resource, do: %__MODULE__{type: :resource}

  @doc """
  Start building a completion response.

  ## Examples

      iex> Response.completion()
      %Response{type: :completion, values: [], hasMore: false}
  """
  @spec completion :: t()
  def completion, do: %__MODULE__{type: :completion}

  @doc """
  Add text content to a tool or resource response.

  For tool responses, adds text to the content array.
  For resource responses, sets the text content.

  ## Parameters

    * `response` - A tool or resource response struct
    * `text` - The text content

  ## Examples

      iex> Response.tool() |> Response.text("Hello world")
      %Response{
        type: :tool,
        content: [%{"type" => "text", "text" => "Hello world"}],
        isError: false
      }
      
      iex> Response.resource() |> Response.text("File contents")
      %Response{type: :resource, contents: %{"text" => "File contents"}}
  """
  @spec text(t(), content :: String.t(), annotations) :: t
  def text(r, text, opts \\ [])

  def text(%{type: :tool} = r, text, opts) when is_binary(text) do
    content = %{"type" => "text", "text" => text}
    content = maybe_add_annotations(content, opts[:annotations])
    add_content(r, content)
  end

  def text(%{type: :resource} = r, text, opts) when is_binary(text) do
    contents = %{"text" => text}
    contents = maybe_add_annotations(contents, opts[:annotations])
    %{r | contents: contents}
  end

  @doc """
  Add JSON-encoded content to a tool response.

  This is a convenience function that automatically encodes data as JSON
  and adds it as text content. Useful for returning structured data from tools.

  ## Parameters

    * `response` - A tool response struct
    * `data` - Any JSON-encodable data structure

  ## Examples

      iex> Response.tool() |> Response.json(%{status: "ok", count: 42})
      %Response{
        type: :tool,
        content: [%{"type" => "text", "text" => "{\\"status\\":\\"ok\\",\\"count\\":42}"}],
        isError: false
      }
      
      iex> Response.tool() |> Response.json([1, 2, 3])
      %Response{
        type: :tool,
        content: [%{"type" => "text", "text" => "[1,2,3]"}],
        isError: false
      }
  """
  @spec json(t(), data :: map, annotations) :: t
  def json(%{type: type} = r, data, opts \\ []) when type in ~w(tool resource)a do
    text(r, JSON.encode!(data), opts)
  end

  @doc """
  Set structured content for a tool response.

  This adds structured JSON content that conforms to the tool's output schema.
  For backward compatibility, this also adds the JSON as text content.

  ## Parameters

    * `response` - A tool response struct
    * `data` - A map containing the structured data

  ## Examples

      iex> Response.tool() |> Response.structured(%{temperature: 22.5, conditions: "Partly cloudy"})
      %Response{
        type: :tool,
        content: [%{"type" => "text", "text" => "{\\"temperature\\":22.5,\\"conditions\\":\\"Partly cloudy\\"}"}],
        structured_content: %{temperature: 22.5, conditions: "Partly cloudy"},
        isError: false
      }
  """
  @spec structured(t(), data :: map) :: t
  def structured(%{type: :tool} = r, data) when is_map(data) do
    r
    |> json(data)
    |> Map.put(:structured_content, data)
  end

  @doc """
  Add image content to a tool response.

  ## Parameters

    * `response` - A tool response struct
    * `data` - Base64 encoded image data
    * `mime_type` - MIME type of the image (e.g., "image/png")

  ## Examples

      iex> Response.tool() |> Response.image(base64_data, "image/png")
      %Response{
        type: :tool,
        content: [%{"type" => "image", "data" => base64_data, "mimeType" => "image/png"}],
        isError: false
      }
  """
  @spec image(t(), blob :: binary, mime_type :: String.t(), annotations) :: t
  def image(%{type: :tool} = r, data, mime_type, opts \\ []) when is_binary(data) and is_binary(mime_type) do
    content = %{"type" => "image", "data" => data, "mimeType" => mime_type}
    content = maybe_add_annotations(content, opts[:annotations])
    add_content(r, content)
  end

  @doc """
  Add audio content to a tool response.

  ## Parameters

    * `response` - A tool response struct
    * `data` - Base64 encoded audio data
    * `mime_type` - MIME type of the audio (e.g., "audio/wav")
    * `opts` - Optional keyword list with:
      * `:transcription` - Optional text transcription of the audio

  ## Examples

      iex> Response.tool() |> Response.audio(audio_data, "audio/wav")
      %Response{
        type: :tool,
        content: [%{"type" => "audio", "data" => audio_data, "mimeType" => "audio/wav"}],
        isError: false
      }
      
      iex> Response.tool() |> Response.audio(audio_data, "audio/wav", transcription: "Hello")
      %Response{
        type: :tool,
        content: [%{
          "type" => "audio",
          "data" => audio_data,
          "mimeType" => "audio/wav",
          "transcription" => "Hello"
        }],
        isError: false
      }
  """
  @spec audio(t(), blob :: binary, mime_type :: String.t(), annotations) :: t
  def audio(%{type: :tool} = r, data, mime_type, opts \\ []) do
    content = %{"type" => "audio", "data" => data, "mimeType" => mime_type}

    content =
      if opts[:transcription],
        do: Map.put(content, "transcription", opts[:transcription]),
        else: content

    content = maybe_add_annotations(content, opts[:annotations])
    add_content(r, content)
  end

  @doc """
  Add an embedded resource reference to a tool response.

  ## Parameters

    * `response` - A tool response struct
    * `uri` - The resource URI
    * `opts` - Optional keyword list with:
      * `:name` - Human-readable name
      * `:description` - Resource description
      * `:mime_type` - MIME type
      * `:text` - Text content (for text resources)
      * `:blob` - Base64 data (for binary resources)

  ## Examples

      iex> Response.tool() |> Response.embedded_resource("file://example.txt",
      ...>   name: "Example File",
      ...>   mime_type: "text/plain",
      ...>   text: "File contents"
      ...> )
  """
  @spec embedded_resource(t, uri :: String.t(), annotations) :: t
  def embedded_resource(%{type: :tool} = r, uri, opts \\ []) do
    resource =
      %{"uri" => uri}
      |> maybe_put("name", opts[:name])
      |> maybe_put("title", opts[:title])
      |> maybe_put("description", opts[:description])
      |> maybe_put("mimeType", opts[:mime_type])
      |> maybe_put("text", opts[:text])
      |> maybe_put("blob", opts[:blob])

    resource = maybe_add_annotations(resource, opts[:annotations])
    add_content(r, %{"type" => "resource", "resource" => resource})
  end

  @doc """
  Add a resource link to a tool response.

  ## Parameters

    * `response` - A tool response struct
    * `uri` - The resource URI
    * `name` - The name of the resource
    * `opts` - Optional keyword list with:
      * `:title` - Human-readable title
      * `:description` - Resource description
      * `:mime_type` - MIME type
      * `:size` - Size in bytes
      * `:annotations` - Optional annotations map

  ## Examples

      iex> Response.tool() |> Response.resource_link("file://main.rs", "main.rs",
      ...>   title: "Main File",
      ...>   description: "Primary application entry point",
      ...>   mime_type: "text/x-rust",
      ...>   annotations: %{audience: ["assistant"], priority: 0.9}
      ...> )
      %Response{
        type: :tool,
        content: [%{
          "type" => "resource_link",
          "uri" => "file://main.rs",
          "name" => "main.rs",
          "title" => "Main File",
          "description" => "Primary application entry point",
          "mimeType" => "text/x-rust",
          "annotations" => %{"audience" => ["assistant"], "priority" => 0.9}
        }],
        isError: false
      }
  """
  @spec resource_link(t, uri :: String.t(), name :: String.t(), annotations) :: t
  def resource_link(%{type: :tool} = r, uri, name, opts \\ []) when is_binary(uri) and is_binary(name) do
    content =
      %{"type" => "resource_link", "uri" => uri, "name" => name}
      |> maybe_put("title", opts[:title])
      |> maybe_put("description", opts[:description])
      |> maybe_put("mimeType", opts[:mime_type])
      |> maybe_put("size", opts[:size])
      |> maybe_add_annotations(opts[:annotations])

    add_content(r, content)
  end

  @doc """
  Mark a tool response as an error and add error message.

  ## Parameters

    * `response` - A tool response struct
    * `message` - The error message

  ## Examples

      iex> Response.tool() |> Response.error("Division by zero")
      %Response{
        type: :tool,
        content: [%{"type" => "text", "text" => "Error: Division by zero"}],
        isError: true
      }
  """
  @spec error(t, message :: String.t()) :: t
  def error(%{type: :tool} = r, message) when is_binary(message) do
    r
    |> text(message)
    |> Map.put(:isError, true)
  end

  @doc """
  Add a user message to a prompt response.

  ## Parameters

    * `response` - A prompt response struct
    * `content` - The message content (string or structured content)

  ## Examples

      iex> Response.prompt() |> Response.user_message("What's the weather?")
      %Response{
        type: :prompt,
        messages: [%{"role" => "user", "content" => "What's the weather?"}]
      }
  """
  @spec user_message(t, term) :: t
  def user_message(%{type: :prompt} = r, content) do
    add_message(r, %{"role" => "user", "content" => build_message_content(content)})
  end

  @doc """
  Add an assistant message to a prompt response.

  ## Parameters

    * `response` - A prompt response struct
    * `content` - The message content (string or structured content)

  ## Examples

      iex> Response.prompt() |> Response.assistant_message("Let me check the weather for you.")
      %Response{
        type: :prompt,
        messages: [%{"role" => "assistant", "content" => "Let me check the weather for you."}]
      }
  """
  @spec assistant_message(t, term) :: t
  def assistant_message(%{type: :prompt} = r, content) do
    add_message(r, %{
      "role" => "assistant",
      "content" => build_message_content(content)
    })
  end

  @doc """
  Add a system message to a prompt response.

  ## Parameters

    * `response` - A prompt response struct
    * `content` - The message content (string or structured content)

  ## Examples

      iex> Response.prompt() |> Response.system_message("You are a helpful weather assistant.")
      %Response{
        type: :prompt,
        messages: [%{"role" => "system", "content" => "You are a helpful weather assistant."}]
      }
  """
  @spec system_message(t, term) :: t
  def system_message(%{type: :prompt} = r, content) do
    add_message(r, %{"role" => "system", "content" => build_message_content(content)})
  end

  @doc """
  Set blob (base64) content for a resource response.

  ## Parameters

    * `response` - A resource response struct
    * `data` - binary data

  ## Examples

      iex> Response.resource() |> Response.blob(data)
      %Response{type: :resource, contents: %{"blob" => base64_data}}
  """
  def blob(%{type: :resource} = r, data) when is_binary(data) do
    %{r | contents: %{"blob" => Base.url_encode64(data, padding: false)}}
  end

  @doc """
  Set optional name for a resource response.

  ## Parameters

    * `response` - A resource response struct
    * `name` - Human-readable name for the resource

  ## Examples

      iex> Response.resource() |> Response.name("Configuration File")
      %Response{type: :resource, metadata: %{name: "Configuration File"}}
  """
  @spec name(t, String.t()) :: t
  def name(%{type: :resource} = r, name) when is_binary(name) do
    put_metadata(r, :name, name)
  end

  @doc """
  Set optional description for a resource response.

  ## Parameters

    * `response` - A resource response struct
    * `desc` - Description of the resource

  ## Examples

      iex> Response.resource() |> Response.description("Application configuration settings")
      %Response{type: :resource, metadata: %{description: "Application configuration settings"}}
  """
  @spec description(t, String.t()) :: t
  def description(%{type: :resource} = r, desc) when is_binary(desc) do
    put_metadata(r, :description, desc)
  end

  @doc """
  Set optional size for a resource response.

  ## Parameters

    * `response` - A resource response struct
    * `size` - Size in bytes

  ## Examples

      iex> Response.resource() |> Response.size(1024)
      %Response{type: :resource, metadata: %{size: 1024}}
  """
  @spec size(t, non_neg_integer) :: t
  def size(%{type: :resource} = r, size) when is_integer(size) and size >= 0 do
    put_metadata(r, :size, size)
  end

  @doc """
  Add a completion value to a completion response.

  ## Parameters

    * `response` - A completion response struct
    * `value` - The completion value
    * `opts` - Optional keyword list with:
      * `:description` - Description of the completion value
      * `:label` - Optional label for the value

  ## Examples

      iex> Response.completion() |> Response.completion_value("tool:calculator", description: "Math calculator tool")
      %Response{
        type: :completion,
        values: [%{"value" => "tool:calculator", "description" => "Math calculator tool"}]
      }
  """
  @spec completion_value(t, value :: String.t(), list(completion_opt)) :: t
        when completion_opt: {:description, String.t() | nil} | {:label, String.t() | nil}
  def completion_value(%{type: :completion} = r, value, opts \\ []) when is_binary(value) do
    completion_item =
      %{"value" => value}
      |> maybe_put("description", opts[:description])
      |> maybe_put("label", opts[:label])

    %{r | values: r.values ++ [completion_item]}
  end

  @doc """
  Add multiple completion values at once.

  ## Parameters

    * `response` - A completion response struct
    * `values` - List of values (strings or maps with value/description/label)

  ## Examples

      iex> Response.completion() |> Response.completion_values(["foo", "bar"])
      %Response{
        type: :completion,
        values: [%{"value" => "foo"}, %{"value" => "bar"}]
      }
      
      iex> Response.completion() |> Response.completion_values([
      ...>   %{value: "foo", description: "Foo option"},
      ...>   %{value: "bar", description: "Bar option"}
      ...> ])
  """
  @spec completion_values(t, list(completion)) :: t
        when completion: %{
               required(:value) => binary,
               optional(:description) => String.t() | nil,
               optional(:label) => String.t() | nil
             }
  def completion_values(%{type: :completion} = r, values) when is_list(values) do
    normalized_values =
      Enum.map(values, fn
        value when is_binary(value) ->
          %{"value" => value}

        %{value: v} = map ->
          %{"value" => v}
          |> maybe_put("description", Map.get(map, :description))
          |> maybe_put("label", Map.get(map, :label))

        %{"value" => _} = map ->
          map
      end)

    %{r | values: r.values ++ normalized_values}
  end

  @doc """
  Set pagination information for completion response.

  ## Parameters

    * `response` - A completion response struct
    * `total` - Total number of available completions
    * `has_more` - Whether more completions are available

  ## Examples

      iex> Response.completion() 
      ...> |> Response.completion_values(["foo", "bar"])
      ...> |> Response.with_pagination(10, true)
      %Response{
        type: :completion,
        values: [%{"value" => "foo"}, %{"value" => "bar"}],
        total: 10,
        hasMore: true
      }
  """
  @spec with_pagination(t, total :: non_neg_integer, has_more? :: boolean) :: t
  def with_pagination(%{type: :completion} = r, total, has_more) when is_integer(total) and is_boolean(has_more) do
    %{r | total: total, hasMore: has_more}
  end

  @doc """
  Build the final response structure.

  Transforms the response struct into the appropriate format for the MCP protocol.

  ## Parameters

    * `response` - A response struct of any type

  ## Examples

      iex> Response.tool() |> Response.text("Hello") |> Response.to_protocol()
      %{"content" => [%{"type" => "text", "text" => "Hello"}], "isError" => false}
      
      iex> Response.prompt() |> Response.user_message("Hi") |> Response.to_protocol()
      %{"messages" => [%{"role" => "user", "content" => "Hi"}]}
      
      iex> Response.resource() |> Response.text("data") |> Response.to_protocol()
      %{"text" => "data"}
  """
  @spec to_protocol(t) :: map
  def to_protocol(%{type: :tool} = r) do
    base = %{"content" => r.content, "isError" => r.isError}

    if r.structured_content,
      do: Map.put(base, "structuredContent", r.structured_content),
      else: base
  end

  def to_protocol(%{type: :prompt} = r) do
    base = %{"messages" => r.messages}

    if Map.get(r, :description),
      do: Map.put(base, "description", r.description),
      else: base
  end

  def to_protocol(%{type: :completion} = r) do
    base = %{"values" => r.values}

    base
    |> maybe_put("total", r.total)
    |> then(fn map -> if r.hasMore, do: Map.put(map, "hasMore", true), else: map end)
  end

  def to_protocol(%{type: :resource} = r, uri, mime_type) do
    string_metadata =
      Map.new(r.metadata, fn {k, v} -> {to_string(k), v} end)

    r.contents
    |> Map.merge(string_metadata)
    |> Map.put("uri", uri)
    |> Map.put("mimeType", mime_type)
  end

  defp add_content(r, content), do: %{r | content: r.content ++ [content]}
  defp add_message(r, message), do: %{r | messages: r.messages ++ [message]}

  defp put_metadata(r, key, value), do: %{r | metadata: Map.put(r.metadata, key, value)}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_message_content(text) when is_binary(text), do: text
  defp build_message_content(content), do: content

  @annotations_schema %{
    last_modified: :datetime,
    priority: {:float, gte: 0.0, lte: 1.0},
    audience: {:list, {:enum, ~w(user assistant)}}
  }

  defp maybe_add_annotations(map, nil), do: map

  defp maybe_add_annotations(map, annotations) do
    {:ok, annotations} = Peri.validate(@annotations_schema, annotations)

    annotations
    |> then(&if(l = &1[:last_modified], do: Map.put(&1, :lastModified, l), else: &1))
    |> Map.delete(:last_modified)
    |> then(fn a -> Map.put(map, "annotations", a) end)
  end
end
