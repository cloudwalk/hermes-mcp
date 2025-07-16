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

      assert result["properties"]["pattern"] == %{
               "type" => "string",
               "pattern" => "^[A-Z]+$"
             }

      assert result["properties"]["short"] == %{"type" => "string", "minLength" => 5}

      assert result["properties"]["long"] == %{
               "type" => "string",
               "maxLength" => 100
             }
    end

    test "converts numeric constraints" do
      schema = %{
        eq_int: {:integer, {:eq, 42}},
        neq_int: {:integer, {:neq, 0}},
        gt_int: {:integer, {:gt, 0}},
        gte_int: {:integer, {:gte, 18}},
        lt_int: {:integer, {:lt, 100}},
        lte_int: {:integer, {:lte, 99}},
        range_int: {:integer, {:range, {1, 10}}},
        eq_float: {:float, {:eq, 3.14}},
        neq_float: {:float, {:neq, 0.0}},
        gt_float: {:float, {:gt, 0.0}},
        gte_float: {:float, {:gte, 1.5}},
        lt_float: {:float, {:lt, 100.0}},
        lte_float: {:float, {:lte, 99.9}},
        range_float: {:float, {:range, {1.0, 10.0}}}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["eq_int"] == %{
               "type" => "integer",
               "const" => 42
             }

      assert result["properties"]["neq_int"] == %{
               "type" => "integer",
               "not" => %{"const" => 0}
             }

      assert result["properties"]["gt_int"] == %{
               "type" => "integer",
               "exclusiveMinimum" => 0
             }

      assert result["properties"]["gte_int"] == %{
               "type" => "integer",
               "minimum" => 18
             }

      assert result["properties"]["lt_int"] == %{
               "type" => "integer",
               "exclusiveMaximum" => 100
             }

      assert result["properties"]["lte_int"] == %{
               "type" => "integer",
               "maximum" => 99
             }

      assert result["properties"]["range_int"] == %{
               "type" => "integer",
               "minimum" => 1,
               "maximum" => 10
             }

      assert result["properties"]["eq_float"] == %{
               "type" => "number",
               "const" => 3.14
             }

      assert result["properties"]["neq_float"] == %{
               "type" => "number",
               "not" => %{"const" => 0.0}
             }

      assert result["properties"]["gt_float"] == %{
               "type" => "number",
               "exclusiveMinimum" => 0.0
             }

      assert result["properties"]["gte_float"] == %{
               "type" => "number",
               "minimum" => 1.5
             }

      assert result["properties"]["lt_float"] == %{
               "type" => "number",
               "exclusiveMaximum" => 100.0
             }

      assert result["properties"]["lte_float"] == %{
               "type" => "number",
               "maximum" => 99.9
             }

      assert result["properties"]["range_float"] == %{
               "type" => "number",
               "minimum" => 1.0,
               "maximum" => 10.0
             }
    end

    test "converts enum types" do
      schema = %{
        status: {:enum, ["active", "inactive", "pending"]},
        role: {:required, {:enum, [:admin, :user, :guest]}}
      }

      result = Schema.to_json_schema(schema)

      assert result["properties"]["status"] == %{
               "enum" => ["active", "inactive", "pending"]
             }

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

      assert descriptions["tags"] ==
               "Optional array of string parameter elements parameter"

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

      assert result ==
               "user.email: is required; age: must be a positive integer; invalid schema"
    end

    test "handles mixed error formats" do
      errors = [
        "Simple error",
        %{path: ["field"], message: "complex error"},
        {:unexpected, "format"}
      ]

      result = Schema.format_errors(errors)

      assert result ==
               "Simple error; field: complex error; {:unexpected, \"format\"}"
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

  describe "normalize/1" do
    test "handles simple atom types" do
      schema = %{
        name: :string,
        age: :integer,
        active: :boolean
      }

      assert Schema.normalize(schema) == schema
    end

    test "handles required fields with simple syntax" do
      schema = %{
        name: {:required, :string},
        email: {:required, :string}
      }

      assert Schema.normalize(schema) == schema
    end

    test "handles fields with constraints and metadata" do
      schema = %{
        text: {:string, max: 150, description: "Sample text"},
        count: {:integer, min: 1, max: 100, description: "Count value"}
      }

      normalized = Schema.normalize(schema)

      assert normalized == %{
               text: {:mcp_field, {:string, {:max, 150}}, [description: "Sample text"]},
               count: {:mcp_field, {:integer, {:range, {1, 100}}}, [description: "Count value"]}
             }
    end

    test "handles required fields with constraints and metadata" do
      schema = %{
        name: {:required, :string, max: 50, description: "User name"}
      }

      normalized = Schema.normalize(schema)

      assert normalized == %{
               name: {:mcp_field, {:required, :string}, [max: 50, description: "User name"]}
             }
    end

    test "handles nested objects" do
      schema = %{
        user:
          {:object,
           %{
             name: {:required, :string},
             age: :integer
           }}
      }

      normalized = Schema.normalize(schema)

      assert normalized == %{
               user: %{
                 name: {:required, :string},
                 age: :integer
               }
             }
    end

    test "handles nested objects with metadata" do
      schema = %{
        profile:
          {:object,
           %{
             name: :string,
             bio: {:string, max: 500}
           }, description: "User profile"}
      }

      normalized = Schema.normalize(schema)

      assert normalized == %{
               profile:
                 {:mcp_field,
                  %{
                    name: :string,
                    bio: {:mcp_field, {:string, {:max, 500}}, []}
                  }, [description: "User profile"]}
             }
    end

    test "handles list types" do
      schema = %{
        tags: {:list, :string},
        scores: {:list, :integer}
      }

      normalized = Schema.normalize(schema)

      assert normalized == %{
               tags: {:list, :string},
               scores: {:list, :integer}
             }
    end

    test "handles list types with metadata" do
      schema = %{
        tags: {:list, :string, description: "Tag list"}
      }

      normalized = Schema.normalize(schema)

      assert normalized == %{
               tags: {:mcp_field, {:list, :string}, [description: "Tag list"]}
             }
    end

    test "handles field macro output format" do
      schema = [
        {:text, {:mcp_field, {:required, :string}, [max: 150, description: "Text field"]}}
      ]

      normalized = Schema.normalize(schema)

      assert normalized == %{
               text: {:mcp_field, {:required, :string}, [max: 150, description: "Text field"]}
             }
    end

    test "handles already normalized mcp_field" do
      schema = %{
        field: {:mcp_field, :string, [description: "Already normalized"]}
      }

      assert Schema.normalize(schema) == schema
    end

    test "handles constraints with defaults" do
      schema = %{
        limit: {:integer, min: 1, max: 100, default: 10, description: "Page limit"}
      }

      normalized = Schema.normalize(schema)

      assert normalized == %{
               limit: {:mcp_field, {:integer, {:range, {1, 100}}}, [default: 10, description: "Page limit"]}
             }
    end
  end

  describe "integration with runtime format" do
    test "complete workflow from runtime format to JSON Schema" do
      runtime_schema = %{
        query: {:required, :string, description: "Search query"},
        limit: {:integer, min: 1, max: 100, default: 10},
        filters:
          {:object,
           %{
             status: {:required, {:enum, ["active", "inactive"]}, type: "string", description: "possible statuses"},
             created_after: :datetime
           }, description: "Search filters"}
      }

      normalized = Schema.normalize(runtime_schema)

      json_schema = Schema.to_json_schema(normalized)

      assert json_schema == %{
               "type" => "object",
               "properties" => %{
                 "query" => %{
                   "type" => "string",
                   "description" => "Search query"
                 },
                 "limit" => %{
                   "type" => "integer",
                   "minimum" => 1,
                   "maximum" => 100
                 },
                 "filters" => %{
                   "type" => "object",
                   "required" => ["status"],
                   "properties" => %{
                     "status" => %{
                       "enum" => ["active", "inactive"],
                       "type" => "string",
                       "description" => "possible statuses"
                     },
                     "created_after" => %{
                       "type" => "string",
                       "format" => "date-time"
                     }
                   },
                   "description" => "Search filters"
                 }
               },
               "required" => ["query"]
             }
    end

    test "runtime format preserves validation behavior" do
      runtime_schema = %{
        email: {:required, :string, format: "email", description: "Email address"},
        age: {:integer, min: 0, max: 150}
      }

      normalized = Schema.normalize(runtime_schema)
      validator = Schema.validator(normalized)

      assert {:ok, _} = validator.(%{email: "test@example.com", age: 25})

      assert {:error, errors} = validator.(%{age: 25})
      assert length(errors) > 0

      assert {:error, errors} = validator.(%{email: "test@example.com", age: 200})
      assert length(errors) > 0
    end
  end
end
