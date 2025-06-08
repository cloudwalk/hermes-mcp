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
               "content" => [%{"type" => "text", "text" => "Error: Division by zero"}],
               "isError" => true
             }
    end

    test "builds an image response" do
      result =
        Response.tool()
        |> Response.image("base64data", "image/png")
        |> Response.to_protocol()

      assert result == %{
               "content" => [%{"type" => "image", "data" => "base64data", "mimeType" => "image/png"}],
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
      assert decoded == %{"status" => "success", "count" => 42, "items" => ["a", "b", "c"]}
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

      assert result == %{
               "blob" => "base64data",
               "uri" => "file://image.png",
               "mimeType" => "image/png"
             }
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
      assert resource_with_blob.contents == %{"blob" => "data"}
    end
  end
end
