defmodule Hermes.Server.HandlersTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Component.Prompt
  alias Hermes.Server.Component.Resource
  alias Hermes.Server.Component.Tool
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers

  defmodule MockServer do
    @moduledoc false
    def __components__(:tool) do
      [
        %Tool{name: "tool_a", description: "Tool A"},
        %Tool{name: "tool_b", description: "Tool B"},
        %Tool{name: "tool_c", description: "Tool C"},
        %Tool{name: "tool_d", description: "Tool D"}
      ]
    end

    def __components__(:prompt) do
      [
        %Prompt{name: "prompt_1", description: "Prompt 1"},
        %Prompt{name: "prompt_2", description: "Prompt 2"},
        %Prompt{name: "prompt_3", description: "Prompt 3"}
      ]
    end

    def __components__(:resource) do
      [
        %Resource{uri: "resource://a", name: "resource_a", mime_type: "text/plain"},
        %Resource{uri: "resource://b", name: "resource_b", mime_type: "text/plain"},
        %Resource{uri: "resource://c", name: "resource_c", mime_type: "text/plain"},
        %Resource{uri: "resource://d", name: "resource_d", mime_type: "text/plain"},
        %Resource{uri: "resource://e", name: "resource_e", mime_type: "text/plain"},
        # Resource templates
        %Resource{
          uri_template: "file:///{path}",
          name: "template_1",
          title: "Project Files",
          description: "Access project files",
          mime_type: "application/octet-stream"
        },
        %Resource{
          uri_template: "db:///{table}/{id}",
          name: "template_2",
          title: "Database Records",
          mime_type: "application/json"
        }
      ]
    end
  end

  describe "maybe_paginate/3" do
    test "returns all items when limit is nil" do
      components = [
        %Tool{name: "a"},
        %Tool{name: "b"},
        %Tool{name: "c"}
      ]

      assert {^components, nil} = Handlers.maybe_paginate(%{}, components, nil)
    end

    test "paginates items when limit is set" do
      components = [
        %Tool{name: "a"},
        %Tool{name: "b"},
        %Tool{name: "c"},
        %Tool{name: "d"}
      ]

      {items, cursor} = Handlers.maybe_paginate(%{}, components, 2)
      assert length(items) == 2
      assert [%Tool{name: "a"}, %Tool{name: "b"}] = items
      assert cursor == Base.encode64("b", padding: false)
    end

    test "returns nil cursor when items don't exceed limit" do
      components = [
        %Tool{name: "a"},
        %Tool{name: "b"}
      ]

      {items, cursor} = Handlers.maybe_paginate(%{}, components, 5)
      assert length(items) == 2
      assert cursor == nil
    end

    test "handles cursor-based pagination" do
      components = [
        %Tool{name: "a"},
        %Tool{name: "b"},
        %Tool{name: "c"},
        %Tool{name: "d"}
      ]

      cursor = Base.encode64("b", padding: false)
      request = %{"params" => %{"cursor" => cursor}}

      {items, next_cursor} = Handlers.maybe_paginate(request, components, 2)
      assert length(items) == 2
      assert [%Tool{name: "c"}, %Tool{name: "d"}] = items
      refute next_cursor
    end

    test "returns empty list when cursor is beyond all items" do
      components = [
        %Tool{name: "a"},
        %Tool{name: "b"}
      ]

      cursor = Base.encode64("z", padding: false)
      request = %{"params" => %{"cursor" => cursor}}

      {items, next_cursor} = Handlers.maybe_paginate(request, components, 2)
      assert items == []
      assert next_cursor == nil
    end
  end

  describe "tools/list with pagination" do
    setup do
      frame = Frame.new()
      {:ok, frame: frame}
    end

    test "returns paginated tools when limit is set", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 2)
      request = %{"method" => "tools/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["tools"]) == 2
      assert response["nextCursor"]
      assert [%{name: "tool_a"}, %{name: "tool_b"}] = response["tools"]
    end

    test "returns all tools when no limit is set", %{frame: frame} do
      request = %{"method" => "tools/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["tools"]) == 4
      refute Map.has_key?(response, "nextCursor")
    end

    test "handles cursor-based pagination", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 2)
      cursor = Base.encode64("tool_b", padding: false)
      request = %{"method" => "tools/list", "params" => %{"cursor" => cursor}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["tools"]) == 2
      refute response["nextCursor"]
      assert [%{name: "tool_c"}, %{name: "tool_d"}] = response["tools"]
    end
  end

  describe "prompts/list with pagination" do
    setup do
      frame = Frame.new()
      {:ok, frame: frame}
    end

    test "returns paginated prompts when limit is set", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 2)
      request = %{"method" => "prompts/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["prompts"]) == 2
      assert response["nextCursor"]
      assert [%{name: "prompt_1"}, %{name: "prompt_2"}] = response["prompts"]
    end

    test "returns all prompts when no limit is set", %{frame: frame} do
      request = %{"method" => "prompts/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["prompts"]) == 3
      refute Map.has_key?(response, "nextCursor")
    end

    test "handles last page correctly", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 2)
      cursor = Base.encode64("prompt_2", padding: false)
      request = %{"method" => "prompts/list", "params" => %{"cursor" => cursor}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["prompts"]) == 1
      refute Map.has_key?(response, "nextCursor")
      assert [%{name: "prompt_3"}] = response["prompts"]
    end
  end

  describe "resources/list with pagination" do
    setup do
      frame = Frame.new()
      {:ok, frame: frame}
    end

    test "returns paginated resources when limit is set", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 3)
      request = %{"method" => "resources/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["resources"]) == 3
      assert response["nextCursor"]

      assert [
               %{name: "resource_a"},
               %{name: "resource_b"},
               %{name: "resource_c"}
             ] = response["resources"]
    end

    test "returns all resources when no limit is set", %{frame: frame} do
      request = %{"method" => "resources/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["resources"]) == 5
      refute Map.has_key?(response, "nextCursor")
    end

    test "handles multiple pages", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 2)

      request1 = %{"method" => "resources/list", "params" => %{}}
      {:reply, response1, _frame} = Handlers.handle(request1, MockServer, frame)

      assert length(response1["resources"]) == 2
      assert response1["nextCursor"]

      request2 = %{
        "method" => "resources/list",
        "params" => %{"cursor" => response1["nextCursor"]}
      }

      {:reply, response2, _frame} = Handlers.handle(request2, MockServer, frame)

      assert length(response2["resources"]) == 2
      assert response2["nextCursor"]

      request3 = %{
        "method" => "resources/list",
        "params" => %{"cursor" => response2["nextCursor"]}
      }

      {:reply, response3, _frame} = Handlers.handle(request3, MockServer, frame)

      assert length(response3["resources"]) == 1
      refute Map.has_key?(response3, "nextCursor")
    end
  end

  describe "resources/templates/list" do
    setup do
      frame = Frame.new()
      {:ok, frame: frame}
    end

    test "returns only resource templates", %{frame: frame} do
      request = %{"method" => "resources/templates/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["resourceTemplates"]) == 2
      refute Map.has_key?(response, "nextCursor")

      assert [
               %{uri_template: "file:///{path}", name: "template_1", title: "Project Files"},
               %{
                 uri_template: "db:///{table}/{id}",
                 name: "template_2",
                 title: "Database Records"
               }
             ] = response["resourceTemplates"]
    end

    test "returns paginated resource templates when limit is set", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 1)
      request = %{"method" => "resources/templates/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["resourceTemplates"]) == 1
      assert response["nextCursor"]
      assert [%{name: "template_1"}] = response["resourceTemplates"]
    end

    test "handles cursor-based pagination for templates", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 1)
      cursor = Base.encode64("template_1", padding: false)
      request = %{"method" => "resources/templates/list", "params" => %{"cursor" => cursor}}

      {:reply, response, _frame} = Handlers.handle(request, MockServer, frame)

      assert length(response["resourceTemplates"]) == 1
      refute Map.has_key?(response, "nextCursor")
      assert [%{name: "template_2"}] = response["resourceTemplates"]
    end
  end

  describe "edge cases" do
    setup do
      frame = Frame.new()
      {:ok, frame: frame}
    end

    test "handles empty component lists", %{frame: frame} do
      defmodule EmptyServer do
        @moduledoc false
        def __components__(_), do: []
      end

      frame = Frame.put_pagination_limit(frame, 10)

      for method <- ["tools/list", "prompts/list", "resources/list"] do
        request = %{"method" => method, "params" => %{}}
        {:reply, response, _frame} = Handlers.handle(request, EmptyServer, frame)

        key = method |> String.split("/") |> List.first()
        assert response[key] == []
        refute Map.has_key?(response, "nextCursor")
      end
    end

    test "handles single item with pagination", %{frame: frame} do
      defmodule SingleItemServer do
        @moduledoc false
        def __components__(:tool), do: [%Tool{name: "only_tool"}]
        def __components__(:prompt), do: []
        def __components__(:resource), do: []
      end

      frame = Frame.put_pagination_limit(frame, 1)
      request = %{"method" => "tools/list", "params" => %{}}

      {:reply, response, _frame} = Handlers.handle(request, SingleItemServer, frame)

      assert length(response["tools"]) == 1
      refute Map.has_key?(response, "nextCursor")
    end

    test "handles invalid cursor gracefully", %{frame: frame} do
      frame = Frame.put_pagination_limit(frame, 2)

      request = %{"method" => "tools/list", "params" => %{"cursor" => "invalid!!!"}}

      assert_raise ArgumentError, fn ->
        Handlers.handle(request, MockServer, frame)
      end
    end
  end
end
