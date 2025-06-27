defmodule Hermes.Server.Component.ToolAnnotationsTest do
  use Hermes.MCP.Case, async: true

  alias Hermes.MCP.Message
  alias Hermes.Server.Component
  alias Hermes.Server.Component.Tool

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
      field :text, {:required, :string}, description: "Text to process"
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
      field :input, {:required, :string}, description: "Input value"
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
      field :data, {:required, :string}, description: "Data to process"
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

  describe "tool annotations" do
    test "tool with annotations in use macro" do
      protocol = Tool.to_protocol(ToolWithAnnotations, nil, "2025-03-26")

      assert protocol["name"] == "tool_with_annotations"
      assert protocol["description"] == "A tool with annotations"
      assert protocol["inputSchema"]["type"] == "object"

      assert protocol["annotations"] == %{
               "confidence" => 0.95,
               "category" => "text-processing",
               "tags" => ["nlp", "text", "analysis"]
             }
    end

    test "tool without annotations" do
      protocol = Tool.to_protocol(ToolWithoutAnnotations, nil, "2025-03-26")

      assert protocol["name"] == "tool_without_annotations"
      assert protocol["description"] == "A tool without annotations"
      assert protocol["inputSchema"]["type"] == "object"
      refute Map.has_key?(protocol, "annotations")
    end

    test "tool with custom annotations implementation" do
      protocol = Tool.to_protocol(ToolWithCustomAnnotations, nil, "2025-03-26")

      assert protocol["name"] == "tool_with_custom_annotations"
      assert protocol["description"] == "A tool with custom annotations implementation"
      assert protocol["inputSchema"]["type"] == "object"

      assert protocol["annotations"] == %{
               "version" => "2.0",
               "experimental" => true,
               "capabilities" => %{
                 "streaming" => false,
                 "batch" => true
               }
             }
    end

    test "annotations callback is optional" do
      # Verify that ToolWithAnnotations implements annotations
      assert function_exported?(ToolWithAnnotations, :annotations, 0)

      # Verify that ToolWithoutAnnotations does not implement annotations
      refute function_exported?(ToolWithoutAnnotations, :annotations, 0)

      # Verify that ToolWithCustomAnnotations implements annotations
      assert function_exported?(ToolWithCustomAnnotations, :annotations, 0)
    end
  end

  describe "tools/list with annotations" do
    defmodule ServerWithAnnotatedTools do
      @moduledoc false
      use Hermes.Server,
        name: "Test Server with Annotations",
        version: "1.0.0",
        capabilities: [:tools]

      component ToolWithAnnotations
      component ToolWithoutAnnotations
      component ToolWithCustomAnnotations

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
      request = init_request("2025-03-26", %{"name" => "TestClient", "version" => "1.0.0"})
      assert {:ok, _} = GenServer.call(server, {:request, request, session_id, %{}})
      notification = build_notification("notifications/initialized", %{})
      assert :ok = GenServer.cast(server, {:notification, notification, session_id, %{}})

      %{server: server, session_id: session_id}
    end

    test "lists tools with and without annotations", %{server: server, session_id: session_id} do
      request = build_request("tools/list", %{})
      {:ok, response_string} = GenServer.call(server, {:request, request, session_id, %{}})

      {:ok, [response]} = Message.decode(response_string)

      assert response["result"]
      tools = response["result"]["tools"]
      assert length(tools) == 3

      # Find each tool and verify its annotations
      tool_with_annotations = Enum.find(tools, &(&1["name"] == "tool_with_annotations"))
      assert tool_with_annotations["annotations"]["confidence"] == 0.95
      assert tool_with_annotations["annotations"]["category"] == "text-processing"
      assert tool_with_annotations["annotations"]["tags"] == ["nlp", "text", "analysis"]

      tool_without_annotations = Enum.find(tools, &(&1["name"] == "tool_without_annotations"))
      refute Map.has_key?(tool_without_annotations, "annotations")

      tool_with_custom = Enum.find(tools, &(&1["name"] == "tool_with_custom_annotations"))
      assert tool_with_custom["annotations"]["version"] == "2.0"
      assert tool_with_custom["annotations"]["experimental"] == true
      assert tool_with_custom["annotations"]["capabilities"]["streaming"] == false
      assert tool_with_custom["annotations"]["capabilities"]["batch"] == true
    end
  end
end
