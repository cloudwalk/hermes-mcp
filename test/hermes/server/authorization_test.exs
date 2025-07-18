defmodule Hermes.Server.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Authorization

  describe "parse_config!/1" do
    test "parses valid configuration" do
      config =
        Authorization.parse_config!(
          authorization_servers: ["https://auth.example.com"],
          realm: "test-realm",
          scopes_supported: ["read", "write"]
        )

      assert config.authorization_servers == ["https://auth.example.com"]
      assert config.realm == "test-realm"
      assert config.scopes_supported == ["read", "write"]
    end

    test "requires authorization_servers" do
      assert_raise Peri.InvalidSchema, fn ->
        Authorization.parse_config!(realm: "test")
      end
    end

    test "uses default realm if not provided" do
      config = Authorization.parse_config!(authorization_servers: ["https://auth.example.com"])

      assert config.realm == "mcp-server"
    end
  end

  describe "build_www_authenticate_header/2" do
    setup do
      config = %{
        authorization_servers: ["https://auth1.com", "https://auth2.com"],
        realm: "test-realm",
        resource_metadata_url: "https://api.example.com/.well-known/oauth-protected-resource"
      }

      {:ok, config: config}
    end

    test "builds basic header", %{config: config} do
      header = Authorization.build_www_authenticate_header(config)

      assert header =~ ~s(realm="test-realm")
      assert header =~ ~s(authorization_servers="https://auth1.com https://auth2.com")

      assert header =~
               ~s(resource_metadata="https://api.example.com/.well-known/oauth-protected-resource")
    end

    test "includes error information when provided", %{config: config} do
      header =
        Authorization.build_www_authenticate_header(config,
          error: "invalid_token",
          error_description: "Token expired"
        )

      assert header =~ ~s(error="invalid_token")
      assert header =~ ~s(error_description="Token expired")
    end

    test "escapes quotes in values", %{config: config} do
      config = %{config | realm: ~s(test "quoted" realm)}
      header = Authorization.build_www_authenticate_header(config)

      assert header =~ ~s(realm="test \\"quoted\\" realm")
    end
  end

  describe "build_resource_metadata/1" do
    test "builds complete metadata" do
      config = %{
        authorization_servers: ["https://auth.example.com"],
        scopes_supported: ["read", "write", "admin"]
      }

      metadata = Authorization.build_resource_metadata(config)

      assert metadata["authorization_servers"] == ["https://auth.example.com"]
      assert metadata["scopes_supported"] == ["read", "write", "admin"]
      assert metadata["bearer_methods_supported"] == ["header"]
      assert metadata["resource_documentation"] == "https://modelcontextprotocol.io"
      assert "RS256" in metadata["resource_signing_alg_values_supported"]
      assert "ES256" in metadata["resource_signing_alg_values_supported"]
    end

    test "excludes nil values" do
      config = %{
        authorization_servers: ["https://auth.example.com"],
        scopes_supported: nil
      }

      metadata = Authorization.build_resource_metadata(config)

      refute Map.has_key?(metadata, "scopes_supported")
    end
  end

  describe "validate_audience/2" do
    test "validates string audience match" do
      token_info = %{aud: "https://api.example.com"}
      assert :ok = Authorization.validate_audience(token_info, "https://api.example.com")
    end

    test "validates audience in list" do
      token_info = %{aud: ["https://api.example.com", "https://other.com"]}
      assert :ok = Authorization.validate_audience(token_info, "https://api.example.com")
    end

    test "rejects mismatched audience" do
      token_info = %{aud: "https://wrong.com"}

      assert {:error, :invalid_audience} =
               Authorization.validate_audience(token_info, "https://api.example.com")
    end

    test "rejects when expected audience not in list" do
      token_info = %{aud: ["https://wrong.com", "https://other.com"]}

      assert {:error, :invalid_audience} =
               Authorization.validate_audience(token_info, "https://api.example.com")
    end

    test "rejects missing audience" do
      assert {:error, :invalid_audience} =
               Authorization.validate_audience(%{}, "https://api.example.com")
    end
  end

  describe "validate_expiry/1" do
    test "validates non-expired token" do
      future_exp = System.system_time(:second) + 3600
      token_info = %{exp: future_exp}

      assert :ok = Authorization.validate_expiry(token_info)
    end

    test "rejects expired token" do
      past_exp = System.system_time(:second) - 3600
      token_info = %{exp: past_exp}

      assert {:error, :expired_token} = Authorization.validate_expiry(token_info)
    end

    test "passes when no expiration" do
      assert :ok = Authorization.validate_expiry(%{})
    end
  end

  describe "validate_scopes/2" do
    test "validates when token has all required scopes" do
      token_info = %{scope: "read write admin"}
      assert :ok = Authorization.validate_scopes(token_info, ["read", "write"])
    end

    test "validates with empty required scopes" do
      token_info = %{scope: "read"}
      assert :ok = Authorization.validate_scopes(token_info, [])
    end

    test "rejects when missing required scope" do
      token_info = %{scope: "read"}

      assert {:error, :insufficient_scope} =
               Authorization.validate_scopes(token_info, ["read", "write"])
    end

    test "rejects when token has no scope" do
      assert {:error, :insufficient_scope} =
               Authorization.validate_scopes(%{}, ["read"])
    end
  end
end
