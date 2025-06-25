defmodule Hermes.Server.Component.Schema do
  @moduledoc false

  @doc """
  Converts a Peri schema definition to JSON Schema format.

  ## Examples

      iex> to_json_schema(%{name: :string, age: {:required, :integer}})
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        },
        "required" => ["age"]
      }
  """
  def to_json_schema(nil), do: %{"type" => "object"}

  def to_json_schema(schema) when is_map(schema) do
    properties =
      Map.new(schema, fn {key, type} -> {to_string(key), convert_type(type)} end)

    required =
      schema
      |> Enum.filter(fn {_key, type} -> required?(type) end)
      |> Enum.map(fn {key, _type} -> to_string(key) end)

    base = %{"type" => "object", "properties" => properties}

    if Enum.empty?(required), do: base, else: Map.put(base, "required", required)
  end

  @doc """
  Converts a Peri schema to prompt argument definitions.

  ## Examples

      iex> to_prompt_arguments(%{language: {:required, :string}, focus: :string})
      [
        %{"name" => "language", "description" => "Required string parameter", "required" => true},
        %{"name" => "focus", "description" => "Optional string parameter", "required" => false}
      ]
  """
  def to_prompt_arguments(nil), do: []

  def to_prompt_arguments(schema) when is_map(schema) do
    Enum.map(schema, fn {key, type} ->
      %{
        "name" => to_string(key),
        "description" => describe_type(type),
        "required" => required?(type)
      }
    end)
  end

  @doc """
  Formats Peri validation errors into a human-readable string.
  """
  def format_errors(errors) when is_list(errors) do
    Enum.map_join(errors, "; ", &format_error/1)
  end

  defp format_error(%{path: path, message: message}) do
    path_str = Enum.join(path, ".")
    if path_str == "", do: message, else: "#{path_str}: #{message}"
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: inspect(error, pretty: true)

  defp convert_type({:required, {:mcp_field, type, opts}}) do
    convert_type({:mcp_field, {:required, type}, opts})
  end

  defp convert_type({:required, type}), do: convert_type(type)

  defp convert_type({:mcp_field, type, opts}) when is_list(opts) do
    base_schema = convert_type(type)

    # For nested objects, we need to merge metadata at the object level
    Enum.reduce(opts, base_schema, fn
      {:format, format}, schema -> Map.put(schema, "format", format)
      {:description, desc}, schema -> Map.put(schema, "description", desc)
      {:type, json_type}, schema -> Map.put(schema, "type", to_string(json_type))
      _, schema -> schema
    end)
  end

  defp convert_type(:string), do: %{"type" => "string"}
  defp convert_type(:integer), do: %{"type" => "integer"}
  defp convert_type(:float), do: %{"type" => "number"}
  defp convert_type(:boolean), do: %{"type" => "boolean"}
  defp convert_type(:any), do: %{}

  defp convert_type(:date), do: %{"type" => "string", "format" => "date"}
  defp convert_type(:time), do: %{"type" => "string", "format" => "time"}
  defp convert_type(:datetime), do: %{"type" => "string", "format" => "date-time"}
  defp convert_type(:naive_datetime), do: %{"type" => "string", "format" => "date-time"}

  defp convert_type({:string, {:regex, %Regex{source: pattern}}}) do
    %{"type" => "string", "pattern" => pattern}
  end

  defp convert_type({:string, {:min, min}}) do
    %{"type" => "string", "minLength" => min}
  end

  defp convert_type({:string, {:max, max}}) do
    %{"type" => "string", "maxLength" => max}
  end

  defp convert_type({:integer, {:min, min}}) do
    %{"type" => "integer", "minimum" => min}
  end

  defp convert_type({:integer, {:max, max}}) do
    %{"type" => "integer", "maximum" => max}
  end

  defp convert_type({:integer, {:range, {min, max}}}) do
    %{"type" => "integer", "minimum" => min, "maximum" => max}
  end

  defp convert_type({:float, {:min, min}}) do
    %{"type" => "number", "minimum" => min}
  end

  defp convert_type({:float, {:max, max}}) do
    %{"type" => "number", "maximum" => max}
  end

  defp convert_type({:float, {:range, {min, max}}}) do
    %{"type" => "number", "minimum" => min, "maximum" => max}
  end

  defp convert_type({:enum, values}) when is_list(values) do
    %{"enum" => values}
  end

  defp convert_type({:enum, values, type}) when is_list(values) do
    base = convert_type(type)
    Map.put(base, "enum", values)
  end

  defp convert_type({:list, item_type}) do
    %{
      "type" => "array",
      "items" => convert_type(item_type)
    }
  end

  defp convert_type({:map, value_type}) do
    %{
      "type" => "object",
      "additionalProperties" => convert_type(value_type)
    }
  end

  defp convert_type({:literal, value}), do: %{"const" => value}

  defp convert_type({:either, {type1, type2}}) do
    %{"oneOf" => [convert_type(type1), convert_type(type2)]}
  end

  defp convert_type({:oneof, types}) when is_list(types) do
    %{"oneOf" => Enum.map(types, &convert_type/1)}
  end

  defp convert_type({type, {:default, _default}}), do: convert_type(type)

  defp convert_type(nested_schema) when is_map(nested_schema) do
    to_json_schema(nested_schema)
  end

  defp convert_type(_unknown), do: %{}

  defp required?({:required, _}), do: true
  defp required?({:mcp_field, type, _opts}), do: required?(type)
  defp required?(_), do: false

  defp describe_type({:required, type}), do: "Required " <> describe_base_type(type)

  defp describe_type({:mcp_field, type, opts}) do
    Keyword.get(opts, :description) || describe_type(type)
  end

  defp describe_type({type, {:default, default}}) do
    "Optional " <> describe_base_type(type) <> " (default: #{to_string(default)})"
  end

  defp describe_type(type), do: "Optional " <> describe_base_type(type)

  defp describe_base_type(:string), do: "string parameter"
  defp describe_base_type(:integer), do: "integer parameter"
  defp describe_base_type(:float), do: "number parameter"
  defp describe_base_type(:boolean), do: "boolean parameter"
  defp describe_base_type({:enum, values}), do: "one of: #{inspect(values, pretty: true)}"
  defp describe_base_type({:list, {type, _}}), do: "array of #{describe_base_type(type)} elements parameter"
  defp describe_base_type({:list, type}), do: "array of #{describe_base_type(type)} elements parameter"
  defp describe_base_type({:map, _}), do: "object parameter"
  defp describe_base_type({type, _}), do: "#{to_string(type)} parameter"
  defp describe_base_type(schema) when is_map(schema), do: "nested object"
  defp describe_base_type(_), do: "parameter"
end
