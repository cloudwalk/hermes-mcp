defmodule Hermes.Server.ComponentFieldMacroTest do
  use ExUnit.Case, async: true

  alias TestTools.DeeplyNestedTool
  alias TestTools.LegacyTool
  alias TestTools.NestedFieldTool
  alias TestTools.SingleNestedFieldTool

  describe "field macro with nested do blocks" do
    test "generates correct JSON Schema with nested fields" do
      json_schema = NestedFieldTool.input_schema()

      assert json_schema == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{
                   "type" => "string",
                   "description" => "Full name"
                 },
                 "address" => %{
                   "type" => "object",
                   "description" => "Mailing address",
                   "properties" => %{
                     "street" => %{"type" => "string"},
                     "city" => %{"type" => "string"},
                     "state" => %{"type" => "string"},
                     "zip" => %{
                       "type" => "string",
                       "format" => "postal-code"
                     }
                   },
                   "required" => ["street", "city"]
                 },
                 "contact" => %{
                   "type" => "object",
                   "properties" => %{
                     "email" => %{
                       "type" => "string",
                       "format" => "email",
                       "description" => "Contact email"
                     },
                     "phone" => %{
                       "type" => "string",
                       "format" => "phone"
                     }
                   }
                 }
               },
               "required" => ["name"]
             }

      # Verify Peri validation still works
      assert {:ok, _} =
               NestedFieldTool.mcp_schema(%{
                 name: "John Doe",
                 address: %{
                   street: "123 Main St",
                   city: "New York",
                   state: "NY",
                   zip: "10001"
                 },
                 contact: %{
                   email: "john@example.com",
                   phone: "+1-555-0123"
                 }
               })

      # Missing required fields should fail
      assert {:error, _} =
               NestedFieldTool.mcp_schema(%{
                 name: "John Doe",
                 address: %{
                   city: "New York"
                   # Missing required street
                 }
               })
    end

    test "supports single field in nested block" do
      json_schema = SingleNestedFieldTool.input_schema()

      assert json_schema == %{
               "type" => "object",
               "properties" => %{
                 "user" => %{
                   "type" => "object",
                   "description" => "User information",
                   "properties" => %{
                     "id" => %{
                       "type" => "string",
                       "format" => "uuid"
                     }
                   },
                   "required" => ["id"]
                 }
               }
             }
    end

    test "supports deeply nested fields" do
      json_schema = DeeplyNestedTool.input_schema()

      assert json_schema["properties"]["organization"]["properties"]["admin"]["properties"]["permissions"] == %{
               "type" => "object",
               "properties" => %{
                 "read" => %{"type" => "boolean"},
                 "write" => %{"type" => "boolean"},
                 "delete" => %{"type" => "boolean"}
               },
               "required" => ["read", "write"]
             }
    end
  end

  describe "cleaner schema syntax without braces" do
    test "allows defining schemas without explicit map braces" do
      defmodule CleanSyntaxTool do
        @moduledoc "Tool demonstrating clean syntax"

        use Hermes.Server.Component, type: :tool

        # No braces needed!
        schema do
          field(:title, {:required, :string}, description: "Title of the item")
          field(:priority, {:enum, ["low", "medium", "high"]}, description: "Priority level")

          field :metadata do
            field(:created_at, :string, format: "date-time")
            field(:tags, {:list, :string})
          end
        end

        @impl true
        def execute(params, frame) do
          {:reply, %{processed: params}, frame}
        end
      end

      json_schema = CleanSyntaxTool.input_schema()

      assert json_schema["properties"]["title"]["description"] == "Title of the item"
      assert json_schema["properties"]["priority"]["enum"] == ["low", "medium", "high"]
      assert json_schema["properties"]["metadata"]["properties"]["created_at"]["format"] == "date-time"
      assert json_schema["required"] == ["title"]
    end
  end

  describe "backward compatibility with legacy schemas" do
    test "legacy Peri schema without field macros still works" do
      json_schema = LegacyTool.input_schema()

      assert json_schema == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{"type" => "string"},
                 "age" => %{"type" => "integer"},
                 "email" => %{"type" => "string"},
                 "tags" => %{
                   "type" => "array",
                   "items" => %{"type" => "string"}
                 },
                 "metadata" => %{
                   "type" => "object",
                   "properties" => %{
                     "created_at" => %{"type" => "string"},
                     "updated_at" => %{"type" => "string"}
                   }
                 }
               },
               "required" => ["name"]
             }
    end

    test "legacy schema Peri validation works correctly" do
      # Valid data
      assert {:ok, _} =
               LegacyTool.mcp_schema(%{
                 name: "John Doe",
                 age: 30,
                 email: "john@example.com",
                 tags: ["developer", "elixir"],
                 metadata: %{
                   created_at: "2024-01-01",
                   updated_at: "2024-01-02"
                 }
               })

      # Default value applied
      assert {:ok, validated} =
               LegacyTool.mcp_schema(%{
                 name: "Jane Doe"
               })

      assert validated.age == 25

      # Missing required field
      assert {:error, _} =
               LegacyTool.mcp_schema(%{
                 age: 30,
                 email: "test@example.com"
               })
    end

    test "mixing field macros and legacy schemas in different tools" do
      # Both styles should work independently
      nested_schema = NestedFieldTool.input_schema()
      legacy_schema = LegacyTool.input_schema()

      # Ensure they are different structures
      refute nested_schema == legacy_schema

      # Both should have valid JSON Schema structure
      assert nested_schema["type"] == "object"
      assert legacy_schema["type"] == "object"
      assert is_map(nested_schema["properties"])
      assert is_map(legacy_schema["properties"])
    end
  end
end
