defmodule Hermes.MCP.ID do
  @moduledoc """
  Utilities for working with MCP message identifiers.
  
  This module provides functions for generating request IDs and progress tokens
  used in the MCP protocol.
  
  ## ID Format
  
  Generated IDs are Base64-encoded strings containing:
  - Timestamp component (to ensure temporal uniqueness)
  - Process identifier hash (to ensure process-level uniqueness)
  - Random component (to ensure collision resistance)
  
  This format ensures uniqueness across nodes, processes, and repeated calls.
  
  ## Examples
  
  ```elixir
  # Generate a standard request ID
  request_id = Hermes.MCP.ID.generate()
  
  # Generate a progress token
  progress_token = Hermes.MCP.ID.generate_progress_token()
  ```
  """
  
  @doc """
  Generates a unique request ID.
  
  Creates a Base64 encoded string containing:
  - Timestamp component (nanoseconds)
  - Process identifier hash
  - Random component
  
  ## Examples
  
      iex> id = Hermes.MCP.ID.generate()
      iex> is_binary(id)
      true
  """
  @spec generate() :: String.t()
  def generate do
    <<
      System.system_time(:nanosecond)::64,
      :erlang.phash2({node(), self()}, 16_777_216)::24,
      :rand.uniform(16_777_216)::24
    >>
    |> Base.url_encode64()
  end
  
  @doc """
  Generates a unique progress token.
  
  Creates a standard request ID with a "progress_" prefix for clarity.
  Progress tokens are used in the MCP protocol to track long-running operations.
  
  ## Examples
  
      iex> token = Hermes.MCP.ID.generate_progress_token()
      iex> String.starts_with?(token, "progress_")
      true
  """
  @spec generate_progress_token() :: String.t()
  def generate_progress_token do
    "progress_" <> generate()
  end
  
  @doc """
  Extracts timestamp from an ID for debugging purposes.
  
  This is primarily useful for troubleshooting timing issues or
  analyzing the sequence of requests.
  
  ## Parameters
  
    * `id` - An ID generated by this module
  
  ## Returns
  
    * The timestamp (in nanoseconds) or nil if the ID cannot be parsed
  
  ## Examples
  
      iex> id = Hermes.MCP.ID.generate()
      iex> timestamp = Hermes.MCP.ID.timestamp_from_id(id)
      iex> is_integer(timestamp)
      true
      
      iex> Hermes.MCP.ID.timestamp_from_id("invalid-id")
      nil
  """
  @spec timestamp_from_id(String.t()) :: integer() | nil
  def timestamp_from_id(id) when is_binary(id) do
    case Base.url_decode64(id) do
      {:ok, <<timestamp::64, _::48>>} -> 
        timestamp
      _ -> 
        nil
    end
  end
  
  @doc """
  Checks if a string appears to be a valid MCP ID.
  
  This performs a basic validation to check if the string conforms
  to the expected ID format.
  
  ## Examples
  
      iex> id = Hermes.MCP.ID.generate()
      iex> Hermes.MCP.ID.valid?(id)
      true
      
      iex> Hermes.MCP.ID.valid?("invalid-id")
      false
  """
  @spec valid?(term()) :: boolean()
  def valid?(id) when is_binary(id) do
    case Base.url_decode64(id) do
      {:ok, <<_timestamp::64, _process::24, _random::24>>} -> true
      _ -> false
    end
  end
  def valid?(_), do: false
  
  @doc """
  Checks if a string appears to be a valid progress token.
  
  Validates that the string starts with "progress_" and the 
  remainder is a valid MCP ID.
  
  ## Examples
  
      iex> token = Hermes.MCP.ID.generate_progress_token()
      iex> Hermes.MCP.ID.valid_progress_token?(token)
      true
      
      iex> Hermes.MCP.ID.valid_progress_token?("not-a-token")
      false
  """
  @spec valid_progress_token?(term()) :: boolean()
  def valid_progress_token?(token) when is_binary(token) do
    case String.split_at(token, 9) do
      {"progress_", rest} -> valid?(rest)
      _ -> false
    end
  end
  def valid_progress_token?(_), do: false
end