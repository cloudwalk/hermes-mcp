defmodule Hermes.Server.ResponseTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Response

  describe "tool responses" do
    test "builds a simple text response" do
      result =
        Response.tool()
        |> Response.text("Hello world")
        |> Response.to_protocol()

      assert result == %{
               "content" => [%{"type" => "text", "text" => "Hello world"}],
               "isError" => false
             }
    end

    test "builds a multi-content response" do
      result =
        Response.tool()
        |> Response.text("Processing...")
        |> Response.text("Result: 42")
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{"type" => "text", "text" => "Processing..."},
                 %{"type" => "text", "text" => "Result: 42"}
               ],
               "isError" => false
             }
    end

    test "builds an error response" do
      result =
        Response.tool()
        |> Response.error("Division by zero")
        |> Response.to_protocol()

      assert result == %{
               "content" => [%{"type" => "text", "text" => "Division by zero"}],
               "isError" => true
             }
    end

    test "builds an image response" do
      result =
        Response.tool()
        |> Response.image("base64data", "image/png")
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "image",
                   "data" => "base64data",
                   "mimeType" => "image/png"
                 }
               ],
               "isError" => false
             }
    end

    test "builds an audio response with transcription" do
      result =
        Response.tool()
        |> Response.audio("audiodata", "audio/wav", transcription: "Hello")
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "audio",
                   "data" => "audiodata",
                   "mimeType" => "audio/wav",
                   "transcription" => "Hello"
                 }
               ],
               "isError" => false
             }
    end

    test "builds an embedded resource response" do
      result =
        Response.tool()
        |> Response.embedded_resource("file://example.txt",
          name: "Example",
          mime_type: "text/plain",
          text: "Contents"
        )
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "resource",
                   "resource" => %{
                     "uri" => "file://example.txt",
                     "name" => "Example",
                     "mimeType" => "text/plain",
                     "text" => "Contents"
                   }
                 }
               ],
               "isError" => false
             }
    end

    test "builds a JSON response" do
      result =
        Response.tool()
        |> Response.json(%{status: "success", count: 42, items: ["a", "b", "c"]})
        |> Response.to_protocol()

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => text
                 }
               ],
               "isError" => false
             } = result

      assert {:ok, decoded} = JSON.decode(text)

      assert decoded == %{
               "status" => "success",
               "count" => 42,
               "items" => ["a", "b", "c"]
             }
    end

    test "builds a resource link response" do
      result =
        Response.tool()
        |> Response.resource_link("file://main.rs", "main.rs",
          title: "Main File",
          description: "Entry point",
          mime_type: "text/x-rust",
          size: 1024
        )
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "resource_link",
                   "uri" => "file://main.rs",
                   "name" => "main.rs",
                   "title" => "Main File",
                   "description" => "Entry point",
                   "mimeType" => "text/x-rust",
                   "size" => 1024
                 }
               ],
               "isError" => false
             }
    end

    test "builds a structured response" do
      result =
        Response.tool()
        |> Response.structured(%{temperature: 22.5, conditions: "Partly cloudy"})
        |> Response.to_protocol()

      assert %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => text
                 }
               ],
               "structuredContent" => %{temperature: 22.5, conditions: "Partly cloudy"},
               "isError" => false
             } = result

      assert {:ok, decoded} = JSON.decode(text)
      assert decoded == %{"temperature" => 22.5, "conditions" => "Partly cloudy"}
    end

    test "builds content with annotations" do
      result =
        Response.tool()
        |> Response.text("Hello", annotations: %{audience: ["user"], priority: 0.8})
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Hello",
                   "annotations" => %{
                     audience: ["user"],
                     priority: 0.8
                   }
                 }
               ],
               "isError" => false
             }
    end

    test "builds image with annotations" do
      result =
        Response.tool()
        |> Response.image("base64data", "image/png", annotations: %{audience: ["assistant"]})
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "image",
                   "data" => "base64data",
                   "mimeType" => "image/png",
                   "annotations" => %{
                     audience: ["assistant"]
                   }
                 }
               ],
               "isError" => false
             }
    end

    test "builds audio with annotations" do
      result =
        Response.tool()
        |> Response.audio("audiodata", "audio/wav",
          transcription: "Hello",
          annotations: %{priority: 1.0}
        )
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "audio",
                   "data" => "audiodata",
                   "mimeType" => "audio/wav",
                   "transcription" => "Hello",
                   "annotations" => %{
                     priority: 1.0
                   }
                 }
               ],
               "isError" => false
             }
    end

    test "builds embedded resource with title and annotations" do
      result =
        Response.tool()
        |> Response.embedded_resource("file://example.txt",
          name: "Example",
          title: "Example File",
          mime_type: "text/plain",
          text: "Contents",
          annotations: %{audience: ["user", "assistant"]}
        )
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "resource",
                   "resource" => %{
                     "uri" => "file://example.txt",
                     "name" => "Example",
                     "title" => "Example File",
                     "mimeType" => "text/plain",
                     "text" => "Contents",
                     "annotations" => %{
                       audience: ["user", "assistant"]
                     }
                   }
                 }
               ],
               "isError" => false
             }
    end

    test "builds resource link with annotations" do
      import DateTime, only: [utc_now: 0]

      now = utc_now()

      result =
        Response.tool()
        |> Response.resource_link("file://main.rs", "main.rs", annotations: %{last_modified: now, priority: 0.5})
        |> Response.to_protocol()

      assert result == %{
               "content" => [
                 %{
                   "type" => "resource_link",
                   "uri" => "file://main.rs",
                   "name" => "main.rs",
                   "annotations" => %{
                     lastModified: now,
                     priority: 0.5
                   }
                 }
               ],
               "isError" => false
             }
    end
  end

  describe "prompt responses" do
    test "builds a simple prompt response" do
      result =
        Response.prompt()
        |> Response.user_message("What's the weather?")
        |> Response.assistant_message("Let me check...")
        |> Response.to_protocol()

      assert result == %{
               "messages" => [
                 %{"role" => "user", "content" => "What's the weather?"},
                 %{"role" => "assistant", "content" => "Let me check..."}
               ]
             }
    end

    test "builds a prompt with description" do
      result =
        "Weather assistant"
        |> Response.prompt()
        |> Response.system_message("You are a weather expert")
        |> Response.to_protocol()

      assert result == %{
               "description" => "Weather assistant",
               "messages" => [
                 %{"role" => "system", "content" => "You are a weather expert"}
               ]
             }
    end
  end

  describe "resource responses" do
    test "builds a text resource response" do
      result =
        Response.resource()
        |> Response.text("File contents")
        |> Response.to_protocol("file://test.txt", "text/plain")

      assert result == %{
               "text" => "File contents",
               "uri" => "file://test.txt",
               "mimeType" => "text/plain"
             }
    end

    test "builds a blob resource response" do
      result =
        Response.resource()
        |> Response.blob("base64data")
        |> Response.to_protocol("file://image.png", "image/png")

      assert %{
               "blob" => _,
               "uri" => "file://image.png",
               "mimeType" => "image/png"
             } = result
    end

    test "builds a resource with metadata" do
      result =
        Response.resource()
        |> Response.text("Contents")
        |> Response.name("Config File")
        |> Response.description("Application configuration")
        |> Response.to_protocol("file://config.json", "application/json")

      assert result == %{
               "text" => "Contents",
               "name" => "Config File",
               "description" => "Application configuration",
               "uri" => "file://config.json",
               "mimeType" => "application/json"
             }
    end

    test "validates resource has content" do
      resource = Response.resource()
      refute resource.contents

      resource_with_text = Response.text(resource, "content")
      assert resource_with_text.contents == %{"text" => "content"}

      resource_with_blob = Response.blob(Response.resource(), "data")
      assert %{"blob" => _} = resource_with_blob.contents
    end

    test "builds a resource with size" do
      result =
        Response.resource()
        |> Response.text("Contents")
        |> Response.size(2048)
        |> Response.to_protocol("file://data.txt", "text/plain")

      assert result == %{
               "text" => "Contents",
               "size" => 2048,
               "uri" => "file://data.txt",
               "mimeType" => "text/plain"
             }
    end

    test "builds resource with text annotations" do
      result =
        Response.resource()
        |> Response.text("Contents", annotations: %{audience: ["user"]})
        |> Response.to_protocol("file://data.txt", "text/plain")

      assert result == %{
               "text" => "Contents",
               "annotations" => %{
                 audience: ["user"]
               },
               "uri" => "file://data.txt",
               "mimeType" => "text/plain"
             }
    end
  end

  describe "completion responses" do
    test "builds a simple completion response" do
      result =
        Response.completion()
        |> Response.completion_value("option1")
        |> Response.completion_value("option2")
        |> Response.to_protocol()

      assert result == %{
               "values" => [
                 %{"value" => "option1"},
                 %{"value" => "option2"}
               ]
             }
    end

    test "builds completion with descriptions" do
      result =
        Response.completion()
        |> Response.completion_value("tool:calc", description: "Calculator tool")
        |> Response.completion_value("tool:search", description: "Search tool", label: "Search")
        |> Response.to_protocol()

      assert result == %{
               "values" => [
                 %{"value" => "tool:calc", "description" => "Calculator tool"},
                 %{"value" => "tool:search", "description" => "Search tool", "label" => "Search"}
               ]
             }
    end

    test "builds completion with pagination" do
      result =
        Response.completion()
        |> Response.completion_values(["a", "b", "c"])
        |> Response.with_pagination(100, true)
        |> Response.to_protocol()

      assert result == %{
               "values" => [
                 %{"value" => "a"},
                 %{"value" => "b"},
                 %{"value" => "c"}
               ],
               "total" => 100,
               "hasMore" => true
             }
    end

    test "builds completion with mixed value formats" do
      result =
        Response.completion()
        |> Response.completion_values([
          "simple",
          %{value: "complex", description: "Complex option"},
          %{"value" => "direct", "description" => "Direct map"}
        ])
        |> Response.to_protocol()

      assert result == %{
               "values" => [
                 %{"value" => "simple"},
                 %{"value" => "complex", "description" => "Complex option"},
                 %{"value" => "direct", "description" => "Direct map"}
               ]
             }
    end
  end
end
