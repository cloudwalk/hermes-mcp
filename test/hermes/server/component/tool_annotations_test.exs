defmodule Hermes.Server.Component.ToolAnnotationsTest do
  use Hermes.MCP.Case, async: true

  alias Hermes.MCP.Message
  alias Hermes.Server.Component

  defmodule ToolWithAnnotations do
    @moduledoc "A tool with annotations"

    use Component,
      type: :tool,
      annotations: %{
        "confidence" => 0.95,
        "category" => "text-processing",
        "tags" => ["nlp", "text", "analysis"]
      }

    alias Hermes.Server.Response

    schema do
      field(:text, {:required, :string}, description: "Text to process")
    end

    @impl true
    def execute(%{text: text}, frame) do
      {:reply, Response.text(Response.tool(), "Processed: #{text}"), frame}
    end
  end

  defmodule ToolWithoutAnnotations do
    @moduledoc "A tool without annotations"

    use Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:input, {:required, :string}, description: "Input value")
    end

    @impl true
    def execute(%{input: input}, frame) do
      {:reply, Response.text(Response.tool(), "Result: #{input}"), frame}
    end
  end

  defmodule ToolWithCustomAnnotations do
    @moduledoc "A tool with custom annotations implementation"

    use Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:data, {:required, :string}, description: "Data to process")
    end

    @impl true
    def execute(%{data: data}, frame) do
      {:reply, Response.text(Response.tool(), "Custom: #{data}"), frame}
    end

    @impl true
    def annotations do
      %{
        "version" => "2.0",
        "experimental" => true,
        "capabilities" => %{
          "streaming" => false,
          "batch" => true
        }
      }
    end
  end

  defmodule ToolWithOutputSchema do
    @moduledoc "A tool with output schema"

    use Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:query, {:required, :string}, description: "Query to process")
      field(:limit, :integer, description: "Result limit")
    end

    output_schema do
      field(
        :results,
        {:required,
         {:list,
          %{
            id: {:required, :string},
            score: {:required, :float},
            title: {:required, :string}
          }}},
        description: "Search results"
      )

      field(:total_count, {:required, :integer}, description: "Total number of results")
      field(:query_time_ms, {:required, :float}, description: "Query execution time")
    end

    @impl true
    def execute(%{query: query}, frame) do
      results = %{
        results: [
          %{id: "1", score: 0.95, title: "Result for #{query}"},
          %{id: "2", score: 0.87, title: "Another result"}
        ],
        total_count: 2,
        query_time_ms: 12.5
      }

      {:reply, Response.structured(Response.tool(), results), frame}
    end
  end

  defmodule ToolWithInvalidOutput do
    @moduledoc "A tool that returns data not matching its output schema"

    use Component, type: :tool

    alias Hermes.Server.Response

    schema do
      field(:input, {:required, :string})
    end

    output_schema do
      field(:status, {:required, :string})
      field(:count, {:required, :integer})
    end

    @impl true
    def execute(%{input: _}, frame) do
      # Intentionally return wrong type for count
      invalid_data = %{
        status: "ok",
        # Wrong type!
        count: "not a number"
      }

      {:reply, Response.structured(Response.tool(), invalid_data), frame}
    end
  end

  describe "tool annotations" do
    test "annotations callback is optional" do
      assert function_exported?(ToolWithAnnotations, :annotations, 0)
      refute function_exported?(ToolWithoutAnnotations, :annotations, 0)
      assert function_exported?(ToolWithCustomAnnotations, :annotations, 0)
    end
  end

  describe "tool output schemas" do
    test "output_schema callback is optional" do
      assert function_exported?(ToolWithOutputSchema, :output_schema, 0)
      refute function_exported?(ToolWithAnnotations, :output_schema, 0)
      refute function_exported?(ToolWithoutAnnotations, :output_schema, 0)
    end

    test "output schema is properly defined" do
      output_schema = ToolWithOutputSchema.output_schema()
      assert output_schema["type"] == "object"
      assert output_schema["required"] == ["results", "total_count", "query_time_ms"]

      results_schema = output_schema["properties"]["results"]
      assert results_schema["type"] == "array"
      assert results_schema["description"] == "Search results"

      item_schema = results_schema["items"]
      assert item_schema["type"] == "object"
      assert item_schema["required"] == ["id", "title", "score"]
    end
  end

  describe "tools/list with annotations" do
    defmodule ServerWithAnnotatedTools do
      @moduledoc false
      use Hermes.Server,
        name: "Test Server with Annotations",
        version: "1.0.0",
        capabilities: [:tools]

      component(ToolWithAnnotations)
      component(ToolWithoutAnnotations)
      component(ToolWithCustomAnnotations)
      component(ToolWithOutputSchema)
      component(ToolWithInvalidOutput)

      @impl true
      def init(_arg, frame), do: {:ok, frame}

      @impl true
      def handle_notification(_notification, frame), do: {:noreply, frame}
    end

    setup do
      start_supervised!(Hermes.Server.Registry)
      transport = start_supervised!(StubTransport)

      # Start session supervisor
      start_supervised!(
        {Hermes.Server.Session.Supervisor, server: ServerWithAnnotatedTools, registry: Hermes.Server.Registry}
      )

      server_opts = [
        module: ServerWithAnnotatedTools,
        name: :test_server,
        registry: Hermes.Server.Registry,
        transport: [layer: StubTransport, name: transport]
      ]

      server = start_supervised!({Hermes.Server.Base, server_opts})

      # Initialize the server
      session_id = "test-session"

      request =
        init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"})

      assert {:ok, _} = GenServer.call(server, {:request, request, session_id, %{}})
      notification = build_notification("notifications/initialized", %{})

      assert :ok =
               GenServer.cast(server, {:notification, notification, session_id, %{}})

      %{server: server, session_id: session_id}
    end

    test "lists tools with and without annotations", %{
      server: server,
      session_id: session_id
    } do
      request = build_request("tools/list", %{})

      {:ok, response_string} =
        GenServer.call(server, {:request, request, session_id, %{}})

      {:ok, [response]} = Message.decode(response_string)

      assert response["result"]
      tools = response["result"]["tools"]
      assert length(tools) == 5

      tool_with_annotations =
        Enum.find(tools, &(&1["name"] == "tool_with_annotations"))

      assert tool_with_annotations["annotations"]["confidence"] == 0.95
      assert tool_with_annotations["annotations"]["category"] == "text-processing"

      assert tool_with_annotations["annotations"]["tags"] == [
               "nlp",
               "text",
               "analysis"
             ]

      tool_without_annotations =
        Enum.find(tools, &(&1["name"] == "tool_without_annotations"))

      refute Map.has_key?(tool_without_annotations, "annotations")

      tool_with_custom =
        Enum.find(tools, &(&1["name"] == "tool_with_custom_annotations"))

      assert tool_with_custom["annotations"]["version"] == "2.0"
      assert tool_with_custom["annotations"]["experimental"]
      assert tool_with_custom["annotations"]["capabilities"]["batch"]
      refute tool_with_custom["annotations"]["capabilities"]["streaming"]
    end

    test "lists tools with output schemas", %{
      server: server,
      session_id: session_id
    } do
      request = build_request("tools/list", %{})

      {:ok, response_string} =
        GenServer.call(server, {:request, request, session_id, %{}})

      {:ok, [response]} = Message.decode(response_string)

      assert response["result"]
      tools = response["result"]["tools"]

      tool_with_output =
        Enum.find(tools, &(&1["name"] == "tool_with_output_schema"))

      assert tool_with_output["outputSchema"]
      assert tool_with_output["outputSchema"]["type"] == "object"

      assert tool_with_output["outputSchema"]["required"] == [
               "results",
               "total_count",
               "query_time_ms"
             ]

      tool_without_output =
        Enum.find(tools, &(&1["name"] == "tool_without_annotations"))

      refute Map.has_key?(tool_without_output, "outputSchema")
    end
  end

  describe "tools/call with output schema validation" do
    defmodule ServerWithOutputSchemaTools do
      @moduledoc false
      use Hermes.Server,
        name: "Test Server with Output Schema Tools",
        version: "1.0.0",
        capabilities: [:tools]

      component(ToolWithOutputSchema)
      component(ToolWithInvalidOutput)
      component(ToolWithoutAnnotations)

      @impl true
      def init(_arg, frame), do: {:ok, frame}

      @impl true
      def handle_notification(_notification, frame), do: {:noreply, frame}
    end

    setup do
      start_supervised!(Hermes.Server.Registry)
      transport = start_supervised!(StubTransport)

      # Start session supervisor
      start_supervised!(
        {Hermes.Server.Session.Supervisor, server: ServerWithOutputSchemaTools, registry: Hermes.Server.Registry}
      )

      server_opts = [
        module: ServerWithOutputSchemaTools,
        name: :test_output_server,
        registry: Hermes.Server.Registry,
        transport: [layer: StubTransport, name: transport]
      ]

      server = start_supervised!({Hermes.Server.Base, server_opts})

      # Initialize the server
      session_id = "test-session-output"

      request =
        init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"})

      assert {:ok, _} = GenServer.call(server, {:request, request, session_id, %{}})
      notification = build_notification("notifications/initialized", %{})

      assert :ok =
               GenServer.cast(server, {:notification, notification, session_id, %{}})

      %{server: server, session_id: session_id}
    end

    test "tool with valid output schema returns structured content", %{
      server: server,
      session_id: session_id
    } do
      request =
        build_request("tools/call", %{
          "name" => "tool_with_output_schema",
          "arguments" => %{"query" => "test search", "limit" => 5}
        })

      {:ok, response_string} =
        GenServer.call(server, {:request, request, session_id, %{}})

      {:ok, [response]} = Message.decode(response_string)

      assert response["result"]
      result = response["result"]

      # Check structured content
      assert result["structuredContent"]
      structured = result["structuredContent"]
      assert structured["total_count"] == 2
      assert structured["query_time_ms"] == 12.5
      assert length(structured["results"]) == 2
      assert hd(structured["results"])["title"] == "Result for test search"

      # Check backward compatibility - content includes JSON
      assert result["content"]
      text_content = Enum.find(result["content"], &(&1["type"] == "text"))
      assert text_content
      decoded = JSON.decode!(text_content["text"])
      assert decoded == structured

      assert result["isError"] == false
    end

    test "tool without output schema works normally", %{
      server: server,
      session_id: session_id
    } do
      request =
        build_request("tools/call", %{
          "name" => "tool_without_annotations",
          "arguments" => %{"input" => "test"}
        })

      {:ok, response_string} =
        GenServer.call(server, {:request, request, session_id, %{}})

      {:ok, [response]} = Message.decode(response_string)

      assert response["result"]
      result = response["result"]

      # No structured content for tools without output schema
      refute Map.has_key?(result, "structuredContent")

      # Regular content is present
      assert result["content"]
      text_content = Enum.find(result["content"], &(&1["type"] == "text"))
      assert text_content["text"] == "Result: test"
      assert result["isError"] == false
    end

    test "tool with invalid output fails validation", %{
      server: server,
      session_id: session_id
    } do
      request =
        build_request("tools/call", %{
          "name" => "tool_with_invalid_output",
          "arguments" => %{"input" => "test"}
        })

      {:ok, response_string} =
        GenServer.call(server, {:request, request, session_id, %{}})

      {:ok, [response]} = Message.decode(response_string)

      assert response["error"]
      error = response["error"]
      assert error["code"] == -32_000
      assert error["message"] == "Tool doesnt conform for it output schema"
      assert error["data"]["errors"]
    end
  end
end
