defmodule Hermes do
  @moduledoc false

  import Peri

  alias Hermes.Server.Transport.SSE, as: ServerSSE
  alias Hermes.Server.Transport.STDIO, as: ServerSTDIO
  alias Hermes.Server.Transport.StreamableHTTP, as: ServerStreamableHTTP
  alias Hermes.Transport.SSE, as: ClientSSE
  alias Hermes.Transport.STDIO, as: ClientSTDIO
  alias Hermes.Transport.StreamableHTTP, as: ClientStreamableHTTP

  @client_transports if Mix.env() == :test,
                       do: [
                         ClientSTDIO,
                         ClientSSE,
                         ClientStreamableHTTP,
                         StubTransport,
                         Hermes.MockTransport
                       ],
                       else: [ClientSTDIO, ClientSSE, ClientStreamableHTTP]

  @server_transports if Mix.env() == :test,
                       do: [
                         ServerSTDIO,
                         ServerStreamableHTTP,
                         ServerSSE,
                         StubTransport
                       ],
                       else: [ServerSTDIO, ServerStreamableHTTP, ServerSSE]

  defschema :client_transport,
    layer: {:required, {:enum, @client_transports}},
    name: {:required, get_schema(:process_name)}

  defschema :server_transport,
    layer: {:required, {:enum, @server_transports}},
    name: {:required, get_schema(:process_name)}

  defschema :process_name, {:either, {:pid, {:custom, &genserver_name/1}}}

  @doc "Checks if hermes should be compiled/used as standalone CLI or OTP library"
  def should_compile_cli? do
    Code.ensure_loaded?(Burrito) and
      Application.get_env(:hermes_mcp, :compile_cli?, false)
  end

  @doc """
  Validates a possible GenServer name using `peri` `:custom` type definition.
  """
  def genserver_name({:via, registry, _}) when is_atom(registry), do: :ok
  def genserver_name({:global, _}), do: :ok
  def genserver_name(name) when is_atom(name), do: :ok

  def genserver_name(val) do
    {:error, "#{inspect(val, pretty: true)} is not a valid name for a GenServer"}
  end

  @doc false
  def exported?(m, f, a) do
    function_exported?(m, f, a) or
      (Code.ensure_loaded?(m) and function_exported?(m, f, a))
  end
end
