defmodule Hermes.Client.Cache do
  @moduledoc false

  alias Hermes.Client.JSONSchemaConverter

  @tool_validators_suffix "_tool_validators"

  # Public API

  @doc """
  Stores tool output validators in the cache.
  Clears existing validators before storing new ones.
  """
  @spec put_tool_validators(client_name :: String.t(), tools :: list(map())) :: :ok
  def put_tool_validators(client, tools) when is_binary(client) and is_list(tools) do
    table_name = tool_validators_table(client)
    ensure_table(table_name)

    :ets.delete_all_objects(table_name)

    tools
    |> Enum.filter(& &1["outputSchema"])
    |> Enum.flat_map(&fetch_tool_validator/1)
    |> then(&:ets.insert(table_name, &1))

    :ok
  end

  defp fetch_tool_validator(%{"outputSchema" => s, "name" => name}) when is_map(s) do
    case JSONSchemaConverter.validator(s) do
      {:ok, validator} -> [{name, validator}]
      {:error, _errors} -> []
    end
  end

  @doc """
  Gets a tool output validator from the cache.
  """
  @spec get_tool_validator(client_name :: String.t(), tool_name :: String.t()) ::
          JSONSchemaConverter.validator() | nil
  def get_tool_validator(client, tool_name) when is_binary(client) and is_binary(tool_name) do
    table_name = tool_validators_table(client)
    ensure_table(table_name)

    case :ets.lookup(table_name, tool_name) do
      [{^tool_name, validator}] -> validator
      [] -> nil
    end
  end

  @doc """
  Clears all tool validators from the cache.
  """
  @spec clear_tool_validators(client_name :: String.t()) :: :ok
  def clear_tool_validators(client) when is_binary(client) do
    table_name = tool_validators_table(client)

    case :ets.whereis(table_name) do
      :undefined ->
        :ok

      _ ->
        :ets.delete_all_objects(table_name)
        :ok
    end
  end

  @doc """
  Cleans up all cache tables for a client process.
  Should be called when the client process terminates.
  """
  @spec cleanup(client_name :: String.t()) :: :ok
  def cleanup(client) when is_binary(client) do
    table_name = tool_validators_table(client)

    case :ets.whereis(table_name) do
      :undefined ->
        :ok

      _ ->
        :ets.delete(table_name)
        :ok
    end
  end

  # Private helpers

  @spec ensure_table(table :: atom) :: :ok
  defp ensure_table(table) when is_atom(table) do
    case :ets.whereis(table) do
      :undefined ->
        :ets.new(table, [:named_table, :private, :set, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  defp tool_validators_table(client) do
    String.to_atom("hermes_client_#{client}#{@tool_validators_suffix}")
  end
end
