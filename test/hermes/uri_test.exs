defmodule Hermes.URITest do
  use ExUnit.Case, async: true

  alias Hermes.URI, as: HermesURI

  describe "join_path/2" do
    test "joins base URL without trailing slash with path with leading slash" do
      base_uri = URI.new!("http://localhost:8000")
      path = "/mcp"

      result = HermesURI.join_path(base_uri, path)
      assert result.path == "/mcp"
    end

    test "joins base URL with trailing slash with path with leading slash" do
      base_uri = URI.new!("http://localhost:8000/")
      path = "/mcp"

      result = HermesURI.join_path(base_uri, path)
      assert result.path == "/mcp"
    end

    test "joins base URL with path to another path" do
      base_uri = URI.new!("http://localhost:8000/api")
      path = "/mcp"

      result = HermesURI.join_path(base_uri, path)
      assert result.path == "/api/mcp"
    end

    test "joins base URL without trailing slash with path without leading slash" do
      base_uri = URI.new!("http://localhost:8000")
      path = "mcp"

      result = HermesURI.join_path(base_uri, path)
      assert result.path == "/mcp"
    end

    test "joins base URL with trailing slash with path without leading slash" do
      base_uri = URI.new!("http://localhost:8000/")
      path = "mcp"

      result = HermesURI.join_path(base_uri, path)
      assert result.path == "/mcp"
    end

    test "handles nil path" do
      base_uri = URI.new!("http://localhost:8000/api")

      result = HermesURI.join_path(base_uri, nil)
      assert result == base_uri
    end
  end

  describe "join_paths/2" do
    test "joins multiple path segments" do
      base_uri = URI.new!("http://localhost:8000")
      paths = ["api", "v1", "users"]

      result = HermesURI.join_paths(base_uri, paths)
      assert result.path == "/api/v1/users"
    end

    test "joins multiple path segments with mixed leading/trailing slashes" do
      base_uri = URI.new!("http://localhost:8000/")
      paths = ["/api/", "v1", "/users"]

      result = HermesURI.join_paths(base_uri, paths)
      assert result.path == "/api/v1/users"
    end
  end
end
