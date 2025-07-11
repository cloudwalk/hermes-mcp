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
          contents: list(map) | nil,
          values: list(map),
          total: integer | nil,
          hasMore: boolean,
          isError: boolean,
          metadata: map
        }

  defstruct [
    :type,
    content: [],
    messages: [],
    contents: nil,
    values: [],
    total: nil,
    hasMore: false,
    isError: false,
    metadata: %{}
  ]

  @doc """
  Start building a tool response.

  ## Examples

      iex> Response.tool()
      %Response{type: :tool, content: [], isError: false}
  """
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
  def resource, do: %__MODULE__{type: :resource}

  @doc """
  Start building a completion response.

  ## Examples

      iex> Response.completion()
      %Response{type: :completion, values: [], hasMore: false}
  """
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
  def text(%{type: :tool} = r, text) when is_binary(text) do
    add_content(r, %{"type" => "text", "text" => text})
  end

  def text(%{type: :resource} = r, text) when is_binary(text) do
    %{r | contents: %{"text" => text}}
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
  def json(%{type: :tool} = r, data) do
    add_content(r, %{"type" => "text", "text" => JSON.encode!(data)})
  end

  def json(%{type: :resource} = r, data) do
    %{r | contents: %{"text" => JSON.encode!(data)}}
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
  def image(%{type: :tool} = r, data, mime_type)
      when is_binary(data) and is_binary(mime_type) do
    add_content(r, %{"type" => "image", "data" => data, "mimeType" => mime_type})
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
  def audio(%{type: :tool} = r, data, mime_type, opts \\ []) do
    content = %{"type" => "audio", "data" => data, "mimeType" => mime_type}

    content =
      if opts[:transcription],
        do: Map.put(content, "transcription", opts[:transcription]),
        else: content

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
  def embedded_resource(%{type: :tool} = r, uri, opts \\ []) do
    resource =
      %{"uri" => uri}
      |> maybe_put("name", opts[:name])
      |> maybe_put("description", opts[:description])
      |> maybe_put("mimeType", opts[:mime_type])
      |> maybe_put("text", opts[:text])
      |> maybe_put("blob", opts[:blob])

    add_content(r, %{"type" => "resource", "resource" => resource})
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
  def system_message(%{type: :prompt} = r, content) do
    add_message(r, %{"role" => "system", "content" => build_message_content(content)})
  end

  @doc """
  Set blob (base64) content for a resource response.

  ## Parameters

    * `response` - A resource response struct
    * `data` - Base64 encoded binary data

  ## Examples

      iex> Response.resource() |> Response.blob(base64_data)
      %Response{type: :resource, contents: %{"blob" => base64_data}}
  """
  def blob(%{type: :resource} = r, data) when is_binary(data) do
    %{r | contents: %{"blob" => data}}
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
  def description(%{type: :resource} = r, desc) when is_binary(desc) do
    put_metadata(r, :description, desc)
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
  def completion_value(%{type: :completion} = r, value, opts \\ [])
      when is_binary(value) do
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
  def with_pagination(%{type: :completion} = r, total, has_more)
      when is_integer(total) and is_boolean(has_more) do
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
  def to_protocol(%{type: :tool} = r) do
    %{"content" => r.content, "isError" => r.isError}
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
end
