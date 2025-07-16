defmodule Hermes.Client.JSONSchemaConverterTest do
  use ExUnit.Case, async: true

  alias Hermes.Client.JSONSchemaConverter

  describe "to_peri/1" do
    test "converts basic string type" do
      assert {:ok, :string} = JSONSchemaConverter.to_peri(%{"type" => "string"})
    end

    test "converts basic number type" do
      assert {:ok, :float} = JSONSchemaConverter.to_peri(%{"type" => "number"})
    end

    test "converts basic integer type" do
      assert {:ok, :integer} = JSONSchemaConverter.to_peri(%{"type" => "integer"})
    end

    test "converts basic boolean type" do
      assert {:ok, :boolean} = JSONSchemaConverter.to_peri(%{"type" => "boolean"})
    end

    test "converts null type" do
      assert {:ok, {:literal, nil}} = JSONSchemaConverter.to_peri(%{"type" => "null"})
    end

    test "converts string with minLength" do
      schema = %{"type" => "string", "minLength" => 3}
      assert {:ok, {:string, {:min, 3}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts string with maxLength" do
      schema = %{"type" => "string", "maxLength" => 10}
      assert {:ok, {:string, {:max, 10}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts string with pattern" do
      schema = %{"type" => "string", "pattern" => "^[a-z]+$"}
      result = JSONSchemaConverter.to_peri(schema)

      assert {:ok, {:string, {:regex, regex}}} = result
      assert Regex.match?(regex, "abc")
      refute Regex.match?(regex, "ABC")
    end

    test "converts string with email format" do
      schema = %{"type" => "string", "format" => "email"}
      result = JSONSchemaConverter.to_peri(schema)

      assert {:ok, {:string, {:regex, regex}}} = result
      assert Regex.match?(regex, "test@example.com")
      refute Regex.match?(regex, "invalid-email")
    end

    test "converts string with date format" do
      schema = %{"type" => "string", "format" => "date"}
      assert {:ok, :date} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts string with date-time format" do
      schema = %{"type" => "string", "format" => "date-time"}
      assert {:ok, :datetime} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts integer with minimum" do
      schema = %{"type" => "integer", "minimum" => 0}
      assert {:ok, {:integer, {:gte, 0}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts integer with maximum" do
      schema = %{"type" => "integer", "maximum" => 100}
      assert {:ok, {:integer, {:lte, 100}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts integer with exclusiveMinimum" do
      schema = %{"type" => "integer", "exclusiveMinimum" => 0}
      assert {:ok, {:integer, {:gt, 0}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts integer with exclusiveMaximum" do
      schema = %{"type" => "integer", "exclusiveMaximum" => 100}
      assert {:ok, {:integer, {:lt, 100}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts number with minimum" do
      schema = %{"type" => "number", "minimum" => 0.0}
      assert {:ok, {:float, {:gte, +0.0}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts number with maximum" do
      schema = %{"type" => "number", "maximum" => 100.0}
      assert {:ok, {:float, {:lte, 100.0}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts const value" do
      schema = %{"const" => "fixed-value"}
      assert {:ok, {:literal, "fixed-value"}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts enum values" do
      schema = %{"enum" => ["red", "green", "blue"]}
      assert {:ok, {:enum, ["red", "green", "blue"]}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts simple object" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        }
      }

      expected = %{
        name: :string,
        age: :integer
      }

      assert {:ok, ^expected} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts object with required fields" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        },
        "required" => ["name"]
      }

      expected = %{
        name: {:required, :string},
        age: :integer
      }

      assert {:ok, ^expected} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts nested object" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "email" => %{"type" => "string", "format" => "email"}
            },
            "required" => ["name"]
          }
        }
      }

      result = JSONSchemaConverter.to_peri(schema)

      assert {:ok, %{user: user_schema}} = result
      assert %{name: {:required, :string}, email: {:string, {:regex, _}}} = user_schema
    end

    test "converts array with items" do
      schema = %{
        "type" => "array",
        "items" => %{"type" => "string"}
      }

      assert {:ok, {:list, :string}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts array with complex items" do
      schema = %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "integer"},
            "name" => %{"type" => "string"}
          }
        }
      }

      expected = {:list, %{id: :integer, name: :string}}
      assert {:ok, ^expected} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts object with additionalProperties" do
      schema = %{
        "type" => "object",
        "additionalProperties" => %{"type" => "string"}
      }

      assert {:ok, {:map, :string}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts oneOf with two schemas" do
      schema = %{
        "oneOf" => [
          %{"type" => "string"},
          %{"type" => "integer"}
        ]
      }

      assert {:ok, {:either, {:string, :integer}}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts oneOf with multiple schemas" do
      schema = %{
        "oneOf" => [
          %{"type" => "string"},
          %{"type" => "integer"},
          %{"type" => "boolean"}
        ]
      }

      assert {:ok, {:oneof, [:string, :integer, :boolean]}} = JSONSchemaConverter.to_peri(schema)
    end

    test "converts multiple types" do
      schema = %{"type" => ["string", "null"]}
      assert {:ok, {:either, {:string, {:literal, nil}}}} = JSONSchemaConverter.to_peri(schema)
    end
  end

  describe "validator/1" do
    test "creates validator for string schema" do
      schema = %{"type" => "string", "minLength" => 3}
      assert {:ok, validator} = JSONSchemaConverter.validator(schema)
      assert {:ok, "hello"} = validator.("hello")
      assert {:error, _} = validator.("hi")
    end

    test "creates validator for object schema" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer", "minimum" => 0}
        },
        "required" => ["name"]
      }

      assert {:ok, validator} = JSONSchemaConverter.validator(schema)

      assert {:ok, _} = validator.(%{"name" => "John", "age" => 30})
      assert {:ok, _} = validator.(%{"name" => "Jane"})
      assert {:error, _} = validator.(%{"age" => 30})
      assert {:error, _} = validator.(%{"name" => "John", "age" => -1})
    end

    test "creates validator for array schema" do
      schema = %{
        "type" => "array",
        "items" => %{"type" => "integer"}
      }

      assert {:ok, validator} = JSONSchemaConverter.validator(schema)

      assert {:ok, [1, 2, 3]} = validator.([1, 2, 3])
      assert {:error, _} = validator.([1, "two", 3])
    end

    test "creates validator for enum schema" do
      schema = %{"enum" => ["red", "green", "blue"]}
      assert {:ok, validator} = JSONSchemaConverter.validator(schema)

      assert {:ok, "red"} = validator.("red")
      assert {:ok, "green"} = validator.("green")
      assert {:error, _} = validator.("yellow")
    end

    test "creates validator for const schema" do
      schema = %{"const" => 42}
      assert {:ok, validator} = JSONSchemaConverter.validator(schema)

      assert {:ok, 42} = validator.(42)
      assert {:error, _} = validator.(43)
      assert {:error, _} = validator.("42")
    end

    test "creates validator for complex nested schema" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string", "minLength" => 1},
              "email" => %{"type" => "string", "format" => "email"},
              "age" => %{"type" => "integer", "minimum" => 0, "maximum" => 150}
            },
            "required" => ["name", "email"]
          },
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"}
          }
        },
        "required" => ["user"]
      }

      assert {:ok, validator} = JSONSchemaConverter.validator(schema)

      valid_data = %{
        "user" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "age" => 30
        },
        "tags" => ["developer", "elixir"]
      }

      assert {:ok, _} = validator.(valid_data)

      invalid_data1 = %{
        "user" => %{
          "name" => "John Doe"
        }
      }

      assert {:error, _} = validator.(invalid_data1)

      invalid_data2 = %{
        "user" => %{
          "name" => "John Doe",
          "email" => "invalid-email"
        }
      }

      assert {:error, _} = validator.(invalid_data2)

      invalid_data3 = %{
        "user" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "age" => 200
        }
      }

      assert {:error, _} = validator.(invalid_data3)
    end
  end

  describe "MCP tool output schema validation" do
    test "validates tool output with structured content" do
      output_schema = %{
        "type" => "object",
        "properties" => %{
          "temperature" => %{
            "type" => "number",
            "description" => "Temperature in celsius"
          },
          "conditions" => %{
            "type" => "string",
            "description" => "Weather conditions description"
          },
          "humidity" => %{
            "type" => "number",
            "description" => "Humidity percentage"
          }
        },
        "required" => ["temperature", "conditions", "humidity"]
      }

      assert {:ok, validator} = JSONSchemaConverter.validator(output_schema)

      valid_output = %{
        "temperature" => 22.5,
        "conditions" => "Partly cloudy",
        "humidity" => 65.0
      }

      assert {:ok, _} = validator.(valid_output)

      invalid_output = %{
        "temperature" => 22.5,
        "conditions" => "Partly cloudy"
      }

      assert {:error, _} = validator.(invalid_output)
    end
  end
end
