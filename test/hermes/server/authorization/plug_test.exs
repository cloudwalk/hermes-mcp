defmodule Hermes.Server.Authorization.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Hermes.Server.Authorization.Plug, as: AuthPlug

  defmodule MockValidator do
    @moduledoc false
    @behaviour Hermes.Server.Authorization.Validator

    @impl true
    def validate_token("valid_token", _config) do
      {:ok,
       %{
         sub: "user123",
         aud: "http://www.example.com/api/test",
         scope: "read write",
         exp: System.system_time(:second) + 3600,
         active: true
       }}
    end

    def validate_token("expired_token", _config) do
      {:error, :expired_token}
    end

    def validate_token("wrong_audience", _config) do
      {:ok,
       %{
         sub: "user123",
         aud: "https://wrong.com",
         scope: "read",
         active: true
       }}
    end

    def validate_token(_, _config) do
      {:error, :invalid_token}
    end
  end

  setup do
    config = [
      authorization_servers: ["https://auth.example.com"],
      realm: "test-realm",
      validator: MockValidator
    ]

    {:ok, config: config, plug_opts: AuthPlug.init(authorization: config)}
  end

  describe "init/1" do
    test "initializes with valid config" do
      opts =
        AuthPlug.init(
          authorization: [
            authorization_servers: ["https://auth.example.com"],
            validator: MockValidator
          ]
        )

      assert opts.config.authorization_servers == ["https://auth.example.com"]
      assert opts.validator == MockValidator
      assert opts.skip_paths == ["/.well-known/oauth-protected-resource"]
    end

    test "uses JWT validator by default" do
      opts = AuthPlug.init(authorization: [authorization_servers: ["https://auth.example.com"]])

      assert opts.validator == Hermes.Server.Authorization.JWTValidator
    end

    test "allows custom skip paths" do
      opts =
        AuthPlug.init(
          authorization: [authorization_servers: ["https://auth.example.com"]],
          skip_paths: ["/health", "/metrics"]
        )

      assert opts.skip_paths == ["/health", "/metrics"]
    end
  end

  describe "call/2 - metadata endpoint" do
    test "serves resource metadata at well-known path", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/.well-known/oauth-protected-resource")
        |> AuthPlug.call(opts)

      assert conn.status == 200

      assert Enum.any?(conn.resp_headers, fn {k, v} ->
               k == "content-type" && String.contains?(v, "application/json")
             end)

      body = JSON.decode!(conn.resp_body)
      assert body["authorization_servers"] == ["https://auth.example.com"]
      assert body["bearer_methods_supported"] == ["header"]
    end

    test "includes cache control header for metadata", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/.well-known/oauth-protected-resource")
        |> AuthPlug.call(opts)

      assert get_resp_header(conn, "cache-control") == ["max-age=3600"]
    end
  end

  describe "call/2 - authentication" do
    test "authenticates valid bearer token", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("authorization", "Bearer valid_token")
        |> AuthPlug.call(opts)

      assert conn.assigns.mcp_auth.sub == "user123"
      assert conn.assigns.mcp_auth.scope == "read write"
      assert conn.assigns.authenticated == true
      refute conn.halted
    end

    test "handles lowercase bearer prefix", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("authorization", "bearer valid_token")
        |> AuthPlug.call(opts)

      assert conn.assigns.authenticated == true
    end

    test "returns 401 for missing token", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/api/test")
        |> AuthPlug.call(opts)

      assert conn.status == 401
      assert conn.halted

      www_auth = conn |> get_resp_header("www-authenticate") |> List.first()
      assert www_auth =~ "Bearer"
      assert www_auth =~ ~s(realm="test-realm")
      assert www_auth =~ ~s(error="invalid_request")
    end

    test "returns 401 for invalid token", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("authorization", "Bearer invalid_token")
        |> AuthPlug.call(opts)

      assert conn.status == 401
      assert conn.halted

      www_auth = conn |> get_resp_header("www-authenticate") |> List.first()
      assert www_auth =~ ~s(error="invalid_token")
    end

    test "returns 401 for expired token", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("authorization", "Bearer expired_token")
        |> AuthPlug.call(opts)

      assert conn.status == 401
      assert conn.halted

      www_auth = conn |> get_resp_header("www-authenticate") |> List.first()
      assert www_auth =~ ~s(error="invalid_token")
      assert www_auth =~ ~s(error_description="The access token expired")
    end

    test "returns 401 for wrong audience", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/api/test")
        |> put_req_header("authorization", "Bearer wrong_audience")
        |> Plug.Conn.put_private(:test_host, "test.example.com")
        |> AuthPlug.call(opts)

      assert conn.status == 401
      assert conn.halted

      www_auth = conn |> get_resp_header("www-authenticate") |> List.first()
      assert www_auth =~ ~s(error="invalid_token")
      assert www_auth =~ ~s(error_description="Token not intended for this resource")
    end

    test "returns JSON-RPC error format", %{plug_opts: opts} do
      conn =
        :get
        |> conn("/api/test")
        |> AuthPlug.call(opts)

      body = JSON.decode!(conn.resp_body)
      assert body["jsonrpc"] == "2.0"
      assert body["error"]["code"] == -32_700
      assert body["id"]
    end
  end

  describe "extract_bearer_token/1" do
    test "extracts valid bearer token" do
      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer abc123")
      assert {:ok, "abc123"} = AuthPlug.extract_bearer_token(conn)
    end

    test "trims whitespace from token" do
      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer  abc123  ")
      assert {:ok, "abc123"} = AuthPlug.extract_bearer_token(conn)
    end

    test "rejects empty bearer token" do
      conn = :get |> conn("/") |> put_req_header("authorization", "Bearer ")
      assert {:error, :no_token} = AuthPlug.extract_bearer_token(conn)
    end

    test "rejects non-bearer auth" do
      conn = :get |> conn("/") |> put_req_header("authorization", "Basic abc123")
      assert {:error, :no_token} = AuthPlug.extract_bearer_token(conn)
    end
  end
end
