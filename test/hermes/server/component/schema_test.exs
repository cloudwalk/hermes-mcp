defmodule Hermes.Server.Component.SchemaTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Component.Schema

  describe "to_json_schema/1" do
    test "converts nil to empty object schema" do
      assert Schema.to_json_schema(nil) == %{"type" => "object"}
    end

    test "converts basic types" do
      schema = %{
        name: :string,
        age: :integer,
        height: :float,
        active: :boolean,
        data: :any
      }

      result = Schema.to_json_schema(schema)

      assert result == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{"type" => "string"},
                 "age" => %{"type" => "integer"},
                 "height" => %{"type" => "number"},
                 "active" => %{"type" => "boolean"},
                 "data" => %{}
               }
             }
    end

    test "handles required fields" do
      schema = %{
        name: {:required, :string},
        age: :integer,
        email: {:required, :string}
      }

      result = Schema.to_json_schema(schema)

      assert %{
               "type" => "object",
               "properties" => %{
                 "name" => %{"type" => "string"},
                 "age" => %{"type" => "integer"},
                 "email" => %{"type" => "string"}
               },
               "required" => required
             } = result

      assert length(required) == 2
      assert "email" in required
      assert "name" in required
    end

    test "converts string constraints" do
      schema = %{
        pattern: {:string, {:regex, ~r/^[A-Z]+$/}},
        short: {:string, {:min, 5}},
        long: {:string, {:max, 100}}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["pattern"] == %{"type" => "string", "pattern" => "^[A-Z]+$"}
      assert result["properties"]["short"] == %{"type" => "string", "minLength" => 5}
      assert result["properties"]["long"] == %{"type" => "string", "maxLength" => 100}
    end

    test "converts numeric constraints" do
      schema = %{
        min_int: {:integer, {:min, 0}},
        max_int: {:integer, {:max, 100}},
        range_int: {:integer, {:range, {1, 10}}},
        min_float: {:float, {:min, 0.0}},
        max_float: {:float, {:max, 100.0}},
        range_float: {:float, {:range, {1.0, 10.0}}}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["min_int"] == %{"type" => "integer", "minimum" => 0}
      assert result["properties"]["max_int"] == %{"type" => "integer", "maximum" => 100}
      assert result["properties"]["range_int"] == %{"type" => "integer", "minimum" => 1, "maximum" => 10}
      assert result["properties"]["min_float"] == %{"type" => "number", "minimum" => 0.0}
      assert result["properties"]["max_float"] == %{"type" => "number", "maximum" => 100.0}
      assert result["properties"]["range_float"] == %{"type" => "number", "minimum" => 1.0, "maximum" => 10.0}
    end

    test "converts enum types" do
      schema = %{
        status: {:enum, ["active", "inactive", "pending"]},
        role: {:required, {:enum, [:admin, :user, :guest]}}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["status"] == %{"enum" => ["active", "inactive", "pending"]}
      assert result["properties"]["role"] == %{"enum" => [:admin, :user, :guest]}
      assert result["required"] == ["role"]
    end

    test "converts collection types" do
      schema = %{
        tags: {:list, :string},
        numbers: {:list, :integer},
        metadata: {:map, :string},
        scores: {:map, :float}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["tags"] == %{
               "type" => "array",
               "items" => %{"type" => "string"}
             }

      assert result["properties"]["numbers"] == %{
               "type" => "array",
               "items" => %{"type" => "integer"}
             }

      assert result["properties"]["metadata"] == %{
               "type" => "object",
               "additionalProperties" => %{"type" => "string"}
             }

      assert result["properties"]["scores"] == %{
               "type" => "object",
               "additionalProperties" => %{"type" => "number"}
             }
    end

    test "converts literal types" do
      schema = %{
        version: {:literal, "1.0.0"},
        type: {:literal, :tool}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["version"] == %{"const" => "1.0.0"}
      assert result["properties"]["type"] == %{"const" => :tool}
    end

    test "converts either and oneof types" do
      schema = %{
        id: {:either, {:string, :integer}},
        value: {:oneof, [:string, :integer, :boolean]}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["id"] == %{
               "oneOf" => [
                 %{"type" => "string"},
                 %{"type" => "integer"}
               ]
             }

      assert result["properties"]["value"] == %{
               "oneOf" => [
                 %{"type" => "string"},
                 %{"type" => "integer"},
                 %{"type" => "boolean"}
               ]
             }
    end

    test "handles nested schemas" do
      schema = %{
        user: %{
          name: {:required, :string},
          profile: %{
            age: :integer,
            bio: :string
          }
        }
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["user"] == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{"type" => "string"},
                 "profile" => %{
                   "type" => "object",
                   "properties" => %{
                     "age" => %{"type" => "integer"},
                     "bio" => %{"type" => "string"}
                   }
                 }
               },
               "required" => ["name"]
             }
    end

    test "ignores default values in conversion" do
      schema = %{
        limit: {:integer, {:default, 10}},
        sort: {:string, {:default, "asc"}}
      }

      result = Schema.to_json_schema(schema)

      # Defaults are handled by Peri, not JSON Schema
      assert result["properties"]["limit"] == %{"type" => "integer"}
      assert result["properties"]["sort"] == %{"type" => "string"}
    end
  end

  describe "to_prompt_arguments/1" do
    test "returns empty list for nil schema" do
      assert Schema.to_prompt_arguments(nil) == []
    end

    test "converts basic schema to arguments" do
      schema = %{
        language: {:required, :string},
        code: {:required, :string},
        focus: :string
      }

      result = Schema.to_prompt_arguments(schema)

      assert length(result) == 3

      assert %{
               "name" => "language",
               "description" => "Required string parameter",
               "required" => true
             } in result

      assert %{
               "name" => "code",
               "description" => "Required string parameter",
               "required" => true
             } in result

      assert %{
               "name" => "focus",
               "description" => "Optional string parameter",
               "required" => false
             } in result
    end

    test "describes different types correctly" do
      schema = %{
        count: :integer,
        rate: :float,
        enabled: :boolean,
        tags: {:list, :string},
        data: {:map, :any},
        status: {:enum, ["on", "off"]},
        config: %{nested: :string}
      }

      result = Schema.to_prompt_arguments(schema)
      descriptions = Map.new(result, fn arg -> {arg["name"], arg["description"]} end)

      assert descriptions["count"] == "Optional integer parameter"
      assert descriptions["rate"] == "Optional number parameter"
      assert descriptions["enabled"] == "Optional boolean parameter"
      assert descriptions["tags"] == "Optional array of string parameter elements parameter"
      assert descriptions["data"] == "Optional object parameter"
      assert descriptions["status"] == ~s(Optional one of: ["on", "off"])
      assert descriptions["config"] == "Optional nested object"
    end
  end

  describe "format_errors/1" do
    test "formats simple error messages" do
      errors = ["Field is required", "Invalid type"]
      assert Schema.format_errors(errors) == "Field is required; Invalid type"
    end

    test "formats errors with paths" do
      errors = [
        %{path: ["user", "email"], message: "is required"},
        %{path: ["age"], message: "must be a positive integer"},
        %{path: [], message: "invalid schema"}
      ]

      result = Schema.format_errors(errors)

      assert result == "user.email: is required; age: must be a positive integer; invalid schema"
    end

    test "handles mixed error formats" do
      errors = [
        "Simple error",
        %{path: ["field"], message: "complex error"},
        {:unexpected, "format"}
      ]

      result = Schema.format_errors(errors)

      assert result == "Simple error; field: complex error; {:unexpected, \"format\"}"
    end
  end

  describe "to_json_schema/1 with mcp_field" do
    test "converts mcp_field with format and description" do
      schema = %{
        email: {:mcp_field, {:required, :string}, format: "email", description: "User's email address"},
        age: {:mcp_field, :integer, description: "Age in years"}
      }

      result = Schema.to_json_schema(schema)

      assert result == %{
               "type" => "object",
               "properties" => %{
                 "email" => %{
                   "type" => "string",
                   "format" => "email",
                   "description" => "User's email address"
                 },
                 "age" => %{
                   "type" => "integer",
                   "description" => "Age in years"
                 }
               },
               "required" => ["email"]
             }
    end

    test "handles nested mcp_field with constraints" do
      schema = %{
        website: {:mcp_field, :string, format: "uri"},
        score: {:mcp_field, {:integer, {:range, {0, 100}}}, description: "Score percentage"}
      }

      result = Schema.to_json_schema(schema)

      assert result == %{
               "type" => "object",
               "properties" => %{
                 "website" => %{
                   "type" => "string",
                   "format" => "uri"
                 },
                 "score" => %{
                   "type" => "integer",
                   "minimum" => 0,
                   "maximum" => 100,
                   "description" => "Score percentage"
                 }
               }
             }
    end

    test "handles required mcp_field" do
      schema = %{
        name: {:required, {:mcp_field, :string, description: "Full name"}}
      }

      result = Schema.to_json_schema(schema)

      assert result == %{
               "type" => "object",
               "properties" => %{
                 "name" => %{
                   "type" => "string",
                   "description" => "Full name"
                 }
               },
               "required" => ["name"]
             }
    end
  end

  describe "to_prompt_arguments/1 with mcp_field" do
    test "uses custom description from mcp_field" do
      schema = %{
        language: {:mcp_field, {:required, :string}, description: "Programming language"},
        focus: {:mcp_field, :string, description: "Areas to focus on"}
      }

      result = Schema.to_prompt_arguments(schema)

      assert result == [
               %{
                 "name" => "language",
                 "description" => "Programming language",
                 "required" => true
               },
               %{
                 "name" => "focus",
                 "description" => "Areas to focus on",
                 "required" => false
               }
             ]
    end

    test "falls back to generated description when not provided" do
      schema = %{
        count: {:mcp_field, :integer, format: "int32"}
      }

      result = Schema.to_prompt_arguments(schema)

      assert result == [
               %{
                 "name" => "count",
                 "description" => "Optional integer parameter",
                 "required" => false
               }
             ]
    end
  end

  describe "nested schemas with mcp_field" do
    test "handles nested schemas with mcp_field metadata" do
      schema = %{
        user: %{
          email: {:mcp_field, {:required, :string}, format: "email", description: "Email address"},
          profile: %{
            age: {:mcp_field, :integer, description: "User age"},
            website: {:mcp_field, :string, format: "uri"}
          }
        },
        settings:
          {:mcp_field,
           %{
             theme: :string,
             notifications: :boolean
           }, description: "User settings object"}
      }

      result = Schema.to_json_schema(schema)

      assert result == %{
               "type" => "object",
               "properties" => %{
                 "user" => %{
                   "type" => "object",
                   "properties" => %{
                     "email" => %{
                       "type" => "string",
                       "format" => "email",
                       "description" => "Email address"
                     },
                     "profile" => %{
                       "type" => "object",
                       "properties" => %{
                         "age" => %{
                           "type" => "integer",
                           "description" => "User age"
                         },
                         "website" => %{
                           "type" => "string",
                           "format" => "uri"
                         }
                       }
                     }
                   },
                   "required" => ["email"]
                 },
                 "settings" => %{
                   "type" => "object",
                   "properties" => %{
                     "theme" => %{"type" => "string"},
                     "notifications" => %{"type" => "boolean"}
                   },
                   "description" => "User settings object"
                 }
               }
             }
    end
  end
end
