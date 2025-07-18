defmodule Hermes.Server.ComponentEmbedsTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Component

  defmodule TestToolWithEmbedsMany do
    @moduledoc "Test tool with embeds_many"

    use Component, type: :tool

    schema do
      embeds_many :users, description: "user list" do
        field(:id, :string, required: true, description: "user id")
      end
    end

    def execute(params, _context), do: {:ok, params}
  end

  defmodule TestToolWithEmbedsOne do
    @moduledoc "Test tool with embeds_one"

    use Component, type: :tool

    schema do
      embeds_one :user, description: "user" do
        field(:id, :string, required: true, description: "user id")
      end
    end

    def execute(params, _context), do: {:ok, params}
  end

  defmodule TestToolWithRequiredEmbeds do
    @moduledoc "Test tool with required embeds"

    use Component, type: :tool

    schema do
      embeds_many :tags, required: true, description: "list of tags" do
        field(:name, :string, required: true)
        field(:value, :string)
      end

      embeds_one :metadata, required: true do
        field(:version, :integer, required: true)
      end
    end

    def execute(params, _context), do: {:ok, params}
  end

  describe "embeds_many" do
    test "generates correct JSON schema for array of objects" do
      schema = TestToolWithEmbedsMany.input_schema()

      expected = %{
        "type" => "object",
        "properties" => %{
          "users" => %{
            "type" => "array",
            "description" => "user list",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "id" => %{
                  "type" => "string",
                  "description" => "user id"
                }
              },
              "required" => ["id"]
            }
          }
        }
      }

      assert schema == expected
    end

    test "validates input correctly" do
      params = %{users: [%{id: "1"}, %{id: "2"}]}
      assert {:ok, ^params} = TestToolWithEmbedsMany.mcp_schema(params)

      params = %{users: [%{id: "1"}, %{name: "John"}]}
      assert {:error, errors} = TestToolWithEmbedsMany.mcp_schema(params)
      assert is_list(errors)
    end
  end

  describe "embeds_one" do
    test "generates correct JSON schema for single object" do
      schema = TestToolWithEmbedsOne.input_schema()

      expected = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "description" => "user",
            "properties" => %{
              "id" => %{
                "type" => "string",
                "description" => "user id"
              }
            },
            "required" => ["id"]
          }
        }
      }

      assert schema == expected
    end

    test "validates input correctly" do
      params = %{user: %{id: "1"}}
      assert {:ok, ^params} = TestToolWithEmbedsOne.mcp_schema(params)

      params = %{user: %{name: "John"}}
      assert {:error, errors} = TestToolWithEmbedsOne.mcp_schema(params)
      assert is_list(errors)
    end
  end

  describe "required embeds" do
    test "generates correct JSON schema with required arrays and objects" do
      schema = TestToolWithRequiredEmbeds.input_schema()

      assert schema["required"] == ["metadata", "tags"]
      assert schema["properties"]["tags"]["type"] == "array"
      assert schema["properties"]["metadata"]["type"] == "object"
    end

    test "validates required fields" do
      assert {:error, _} = TestToolWithRequiredEmbeds.mcp_schema(%{})

      params = %{
        tags: [%{name: "env", value: "prod"}],
        metadata: %{version: 1}
      }

      assert {:ok, ^params} = TestToolWithRequiredEmbeds.mcp_schema(params)
    end
  end
end
