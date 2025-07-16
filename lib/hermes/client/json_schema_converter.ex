defmodule Hermes.Client.JSONSchemaConverter do
  @moduledoc false

  @type json_schema :: map()
  @type peri_schema :: Peri.schema_def()

  @doc """
  Converts a JSON Schema to a Peri schema.
  """
  @spec to_peri(json_schema()) :: {:ok, peri_schema()} | {:error, list(Peri.Error.t())}
  def to_peri(json_schema) when is_map(json_schema) do
    schema = convert_schema(json_schema)
    Peri.validate_schema(schema)
  end

  defp convert_schema(%{"type" => "object"} = schema) do
    convert_object(schema)
  end

  defp convert_schema(%{"type" => "array"} = schema) do
    convert_array(schema)
  end

  defp convert_schema(%{"type" => "string"} = schema) do
    convert_string(schema)
  end

  defp convert_schema(%{"type" => "number"} = schema) do
    convert_number(schema)
  end

  defp convert_schema(%{"type" => "integer"} = schema) do
    convert_integer(schema)
  end

  defp convert_schema(%{"type" => "boolean"}) do
    :boolean
  end

  defp convert_schema(%{"type" => "null"}) do
    {:literal, nil}
  end

  defp convert_schema(%{"type" => types} = schema) when is_list(types) do
    schemas =
      Enum.map(types, fn type ->
        convert_schema(Map.put(schema, "type", type))
      end)

    case schemas do
      [single] -> single
      [first, second] -> {:either, {first, second}}
      multiple -> {:oneof, multiple}
    end
  end

  defp convert_schema(%{"const" => value}) do
    {:literal, value}
  end

  defp convert_schema(%{"enum" => values}) when is_list(values) do
    {:enum, values}
  end

  defp convert_schema(%{"oneOf" => schemas}) when is_list(schemas) do
    converted = Enum.map(schemas, &convert_schema/1)

    case converted do
      [single] -> single
      [first, second] -> {:either, {first, second}}
      multiple -> {:oneof, multiple}
    end
  end

  defp convert_schema(%{"anyOf" => schemas}) when is_list(schemas) do
    convert_schema(%{"oneOf" => schemas})
  end

  defp convert_schema(%{"allOf" => schemas}) when is_list(schemas) do
    merged =
      Enum.reduce(schemas, %{}, fn schema, acc ->
        case convert_schema(schema) do
          map when is_map(map) -> Map.merge(acc, map)
          other -> other
        end
      end)

    merged
  end

  defp convert_schema(%{"not" => schema}) do
    inner = convert_schema(schema)

    {:custom,
     fn value ->
       case Peri.validate(inner, value) do
         {:ok, _} -> {:error, "Value matches forbidden schema"}
         {:error, _} -> {:ok, value}
       end
     end}
  end

  defp convert_schema(%{"additionalProperties" => add_props}) when is_map(add_props) do
    inner_schema = convert_schema(add_props)
    {:map, inner_schema}
  end

  defp convert_schema(_), do: :any

  defp convert_object(%{"properties" => properties} = schema) do
    required = Map.get(schema, "required", [])

    Map.new(properties, fn {key, prop_schema} ->
      peri_type = convert_schema(prop_schema)

      final_type =
        if key in required do
          {:required, peri_type}
        else
          peri_type
        end

      {String.to_atom(key), final_type}
    end)
  end

  defp convert_object(%{"additionalProperties" => add_props}) when is_map(add_props) do
    {:map, convert_schema(add_props)}
  end

  defp convert_object(_), do: %{}

  defp convert_array(%{"items" => items} = schema) do
    item_schema = convert_schema(items)
    constraints? = Map.keys(schema) in ~w(minItems maxItems uniqueItems)

    if constraints?,
      do: validate_array_constraints(schema),
      else: {:list, item_schema}
  end

  defp convert_array(_), do: {:list, :any}

  defp validate_array_constraints(%{} = schema) do
    schema
    |> Map.keys()
    |> Enum.reduce([], fn
      %{"minItems" => min}, acc -> [(&min_length_array_validator(&1, min)) | acc]
      %{"maxItems" => max}, acc -> [(&max_length_array_validator(&1, max)) | acc]
      %{"uniqueItems" => false}, acc -> [fn _ -> :ok end | acc]
      %{"uniqueItems" => true}, acc -> [(&unique_items_array_validator/1) | acc]
      _, acc -> acc
    end)
    |> then(&{:custom, fn array -> validate_array(array, &1) end})
  end

  defp min_length_array_validator(items, min) do
    if length(items) < min,
      do: {:error, "expected array with at least %{min} length", min: min},
      else: :ok
  end

  defp max_length_array_validator(items, max) do
    if length(items) > max,
      do: {:error, "expected array with at max %{max} length", max: max},
      else: :ok
  end

  defp unique_items_array_validator(items) do
    unique? = Enum.empty?(items -- Enum.uniq(items))

    if unique?,
      do: {:error, "expected array with unique elems", []},
      else: :ok
  end

  defp validate_array(array, validators) do
    Enum.reduce_while(validators, :ok, fn validator, acc ->
      case validator.(array) do
        :ok -> {:cont, acc}
        err -> {:halt, err}
      end
    end)
  end

  defp convert_string(schema) do
    :string
    |> apply_constraint(schema, "minLength", :min)
    |> apply_constraint(schema, "maxLength", :max)
    |> apply_constraint(schema, "pattern", fn pattern ->
      {:regex, Regex.compile!(pattern)}
    end)
    |> apply_constraint(schema, "format", fn format ->
      case format do
        "email" -> {:regex, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/}
        "uri" -> {:regex, ~r/^[a-zA-Z][a-zA-Z\d+.-]*:/}
        "date" -> :date
        "time" -> :time
        "date-time" -> :datetime
        _ -> nil
      end
    end)
  end

  defp convert_number(schema) do
    :float
    |> apply_constraint(schema, "minimum", :gte)
    |> apply_constraint(schema, "maximum", :lte)
    |> apply_constraint(schema, "exclusiveMinimum", :gt)
    |> apply_constraint(schema, "exclusiveMaximum", :lt)
    |> apply_constraint(schema, "multipleOf", fn mult ->
      {:custom,
       fn value ->
         if rem(value * 100, mult * 100) == 0 do
           {:ok, value}
         else
           {:error, "Value must be a multiple of #{mult}"}
         end
       end}
    end)
  end

  defp convert_integer(schema) do
    :integer
    |> apply_constraint(schema, "minimum", :gte)
    |> apply_constraint(schema, "maximum", :lte)
    |> apply_constraint(schema, "exclusiveMinimum", :gt)
    |> apply_constraint(schema, "exclusiveMaximum", :lt)
    |> apply_constraint(schema, "multipleOf", fn mult ->
      {:custom,
       fn value ->
         if rem(value, mult) == 0 do
           {:ok, value}
         else
           {:error, "Value must be a multiple of #{mult}"}
         end
       end}
    end)
  end

  defp apply_constraint({base, constraint}, schema, json_key, handler) when is_tuple(constraint) do
    case apply_constraint(base, schema, json_key, handler) do
      {_base, new_constraint} -> {base, [constraint, new_constraint]}
      base -> {base, constraint}
    end
  end

  defp apply_constraint(base, schema, json_key, peri_constraint) when is_atom(peri_constraint) do
    case Map.get(schema, json_key) do
      nil -> base
      value -> {base, {peri_constraint, value}}
    end
  end

  defp apply_constraint(base, schema, json_key, converter) when is_function(converter) do
    case Map.get(schema, json_key) do
      nil ->
        base

      value ->
        case converter.(value) do
          nil -> base
          {:regex, regex} when base == :string -> {:string, {:regex, regex}}
          :date -> :date
          :time -> :time
          :datetime -> :datetime
          constraint -> {base, constraint}
        end
    end
  end

  @type validator :: (term() -> {:ok, term()} | {:error, list(Peri.Error.t())})

  @doc """
  Creates a validator function from a JSON Schema.

  Returns a function that takes a value and returns either
  `{:ok, value}` or `{:error, errors}`.
  """
  @spec validator(json_schema()) :: {:ok, validator} | {:error, list(Peri.Error.t())}
  def validator(json_schema) do
    with {:ok, peri_schema} <- to_peri(json_schema) do
      {:ok, fn value -> Peri.validate(peri_schema, value) end}
    end
  end
end
