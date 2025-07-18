defmodule OauthExample.Tools.SecureOperation do
  @moduledoc "A tool that demonstrates OAuth scope-based authorization"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  schema do
    %{
      operation: {:required, {:enum, ["read_data", "write_data", "admin_action"]}},
      data: :string
    }
  end

  @impl true
  def execute(%{operation: operation} = params, frame) do
    case {operation, check_authorization(operation, frame)} do
      {_, {:error, reason}} ->
        {:error, build_error(reason), frame}

      {"read_data", :ok} ->
        result = %{
          result: "Successfully read data",
          user: Frame.get_auth_subject(frame),
          data: params[:data] || "default data"
        }

        {:reply, Response.json(Response.tool(), result), frame}

      {"write_data", :ok} ->
        result = %{
          result: "Successfully wrote data",
          user: Frame.get_auth_subject(frame),
          data: params[:data] || "new data"
        }

        {:reply, Response.json(Response.tool(), result), frame}

      {"admin_action", :ok} ->
        result = %{
          result: "Admin action completed",
          user: Frame.get_auth_subject(frame),
          admin_info: %{
            all_scopes: Frame.get_auth_scopes(frame),
            client_id: Frame.get_auth(frame)[:client_id]
          }
        }

        {:reply, Response.json(Response.tool(), result), frame}
    end
  end

  defp check_authorization("read_data", frame) do
    if Frame.authenticated?(frame) do
      :ok
    else
      {:error, "Authentication required"}
    end
  end

  defp check_authorization("write_data", frame) do
    cond do
      not Frame.authenticated?(frame) ->
        {:error, "Authentication required"}

      not Frame.has_scope?(frame, "write") ->
        {:error, "This operation requires 'write' scope"}

      true ->
        :ok
    end
  end

  defp check_authorization("admin_action", frame) do
    cond do
      not Frame.authenticated?(frame) ->
        {:error, "Authentication required"}

      not Frame.has_scope?(frame, "admin") ->
        {:error, "This operation requires 'admin' scope"}

      true ->
        :ok
    end
  end

  defp build_error(message) do
    Hermes.MCP.Error.execution("unauthorized", %{message: message})
  end
end
