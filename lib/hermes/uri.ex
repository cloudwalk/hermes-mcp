defmodule Hermes.URI do
  @moduledoc """
  URI utilities for handling URL paths consistently.
  """

  @doc """
  Joins a base URI with a path segment, handling trailing and leading slashes correctly.

  ## Examples
      iex> Hermes.URI.join_path(URI.new!("http://localhost:8000"), "/mcp")
      %URI{scheme: "http", host: "localhost", port: 8000, path: "/mcp"}
      
      iex> Hermes.URI.join_path(URI.new!("http://localhost:8000/"), "/mcp")
      %URI{scheme: "http", host: "localhost", port: 8000, path: "/mcp"}
      
      iex> Hermes.URI.join_path(URI.new!("http://localhost:8000/api"), "/mcp")
      %URI{scheme: "http", host: "localhost", port: 8000, path: "/api/mcp"}
  """
  @spec join_path(URI.t(), String.t()) :: URI.t()
  def join_path(base_uri, path) when is_binary(path) do
    base_path = base_uri.path || ""

    segments =
      [base_path, path]
      |> Enum.map(&String.trim(&1, "/"))
      |> Enum.reject(&(&1 == ""))

    normalized_path = "/" <> Enum.join(segments, "/")
    %{base_uri | path: normalized_path}
  end

  def join_path(base_uri, nil), do: base_uri

  @doc """
  Joins a base URI with multiple path segments, handling trailing and leading slashes correctly.
  """
  @spec join_paths(URI.t(), [String.t()]) :: URI.t()
  def join_paths(base_uri, paths) when is_list(paths) do
    base_path = base_uri.path || ""

    segments =
      [base_path | paths]
      |> Enum.map(&String.trim(&1, "/"))
      |> Enum.reject(&(&1 == ""))

    normalized_path = "/" <> Enum.join(segments, "/")
    %{base_uri | path: normalized_path}
  end
end
