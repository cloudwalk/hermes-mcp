defmodule Hermes.Server.Authorization.Plug do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Hermes.MCP.Error
  alias Hermes.Server.Authorization

  @well_known_path "/.well-known/oauth-protected-resource"

  @impl Plug
  def init(opts) do
    config = Authorization.parse_config!(opts[:authorization] || opts)

    validator =
      case config[:validator] do
        nil -> Authorization.JWTValidator
        module when is_atom(module) -> module
        _ -> raise ArgumentError, "Invalid validator configuration"
      end

    %{
      config: config,
      validator: validator,
      skip_paths: opts[:skip_paths] || [@well_known_path]
    }
  end

  @impl Plug
  def call(%{request_path: path} = conn, %{skip_paths: skip_paths, config: config} = opts) do
    cond do
      path == @well_known_path ->
        send_metadata_response(conn, config)

      path in skip_paths ->
        conn

      true ->
        authenticate(conn, opts)
    end
  end

  defp authenticate(conn, %{config: config, validator: validator}) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, token_info} <- validator.validate_token(token, config),
         :ok <- Authorization.validate_audience(token_info, get_server_uri(conn)),
         :ok <- Authorization.validate_expiry(token_info) do
      conn
      |> assign(:mcp_auth, token_info)
      |> assign(:authenticated, true)
    else
      {:error, :no_token} ->
        send_unauthorized(conn, config, error: "invalid_request")

      {:error, :invalid_token} ->
        send_unauthorized(conn, config, error: "invalid_token")

      {:error, :expired_token} ->
        send_unauthorized(conn, config,
          error: "invalid_token",
          error_description: "The access token expired"
        )

      {:error, :invalid_audience} ->
        send_unauthorized(conn, config,
          error: "invalid_token",
          error_description: "Token not intended for this resource"
        )

      {:error, _} ->
        send_unauthorized(conn, config, error: "invalid_token")
    end
  end

  @doc """
  Extracts bearer token from Authorization header.
  """
  def extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 ->
        {:ok, String.trim(token)}

      ["bearer " <> token] when byte_size(token) > 0 ->
        # Handle lowercase for compatibility
        {:ok, String.trim(token)}

      _ ->
        {:error, :no_token}
    end
  end

  defp send_unauthorized(conn, config, opts) do
    www_authenticate = Authorization.build_www_authenticate_header(config, opts)

    error =
      Error.protocol(:parse_error, %{
        error: opts[:error] || "unauthorized",
        http_status: 401
      })

    {:ok, body} = Error.to_json_rpc(error)

    conn
    |> put_resp_header("www-authenticate", www_authenticate)
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
    |> halt()
  end

  defp send_metadata_response(conn, config) do
    metadata = Authorization.build_resource_metadata(config)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "max-age=3600")
    |> send_resp(200, JSON.encode!(metadata))
    |> halt()
  end

  defp get_server_uri(conn) do
    scheme = if conn.scheme == :https, do: "https", else: "http"

    port_part =
      case {conn.scheme, conn.port} do
        {:https, 443} -> ""
        {:http, 80} -> ""
        {_, port} -> ":#{port}"
      end

    "#{scheme}://#{conn.host}#{port_part}#{conn.request_path}"
  end
end
