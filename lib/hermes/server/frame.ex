defmodule Hermes.Server.Frame do
  @moduledoc """
  Server frame for maintaining state across MCP message handling.

  Similar to LiveView's Socket or Plug.Conn, the Frame provides a consistent
  interface for storing and updating server state throughout the request lifecycle.

  ## Usage

      # Create a new frame
      frame = Frame.new()

      # Assign values
      frame = Frame.assign(frame, :user_id, 123)
      frame = Frame.assign(frame, %{status: :active, count: 0})

      # Conditional assignment
      frame = Frame.assign_new(frame, :timestamp, fn -> DateTime.utc_now() end)

  ## Fields

  - `assigns` - A map containing arbitrary data assigned during request processing
  - `initialized` - Boolean indicating if the server has been initialized
  - `private` - A map for framework-internal session data (similar to Plug.Conn.private)
  - `request` - The current MCP request being processed (if any)

  ## Session Context (private)

  The `private` field stores session-level context that persists across requests:
  - `session_id` - Unique identifier for the client session
  - `client_info` - Client information from initialization (name, version)
  - `client_capabilities` - Negotiated client capabilities
  - `protocol_version` - Active MCP protocol version

  ## Request Context

  The `request` field stores the current request being processed:
  - `id` - Request ID for correlation
  - `method` - The MCP method being executed
  - `params` - Raw request parameters (before validation)
  """

  @type private_t :: %{
          optional(:session_id) => String.t(),
          optional(:client_info) => map(),
          optional(:client_capabilities) => map(),
          optional(:protocol_version) => String.t()
        }

  @type request_t :: %{
          id: String.t(),
          method: String.t(),
          params: map()
        }

  @type http_t :: %{
          type: :http,
          req_headers: [{String.t(), String.t()}],
          query_params: %{optional(String.t()) => String.t()} | nil,
          remote_ip: term,
          scheme: :http | :https,
          host: String.t(),
          port: non_neg_integer,
          request_path: String.t()
        }

  @type stdio_t :: %{
          type: :stdio,
          os_pid: non_neg_integer,
          env: map
        }

  @type transport_t :: http_t | stdio_t

  @type t :: %__MODULE__{
          assigns: Enumerable.t(),
          initialized: boolean,
          private: private_t,
          request: request_t | nil,
          transport: transport_t
        }

  defstruct assigns: %{}, initialized: false, private: %{}, request: nil, transport: %{}

  @doc """
  Creates a new frame with optional initial assigns.

  ## Examples

      iex> Frame.new()
      %Frame{assigns: %{}, initialized: false}

      iex> Frame.new(%{user: "alice"})
      %Frame{assigns: %{user: "alice"}, initialized: false}
  """
  @spec new :: t
  @spec new(assigns :: Enumerable.t()) :: t
  def new(assigns \\ %{}), do: struct(__MODULE__, assigns: assigns)

  @doc """
  Assigns a value or multiple values to the frame.

  ## Examples

      # Single assignment
      frame = Frame.assign(frame, :status, :active)

      # Multiple assignments via map
      frame = Frame.assign(frame, %{status: :active, count: 5})

      # Multiple assignments via keyword list
      frame = Frame.assign(frame, status: :active, count: 5)
  """
  @spec assign(t, Enumerable.t()) :: t
  @spec assign(t, key :: atom, value :: any) :: t
  def assign(%__MODULE__{} = frame, assigns) when is_map(assigns) or is_list(assigns) do
    Enum.reduce(assigns, frame, fn {key, value}, frame -> assign(frame, key, value) end)
  end

  def assign(%__MODULE__{} = frame, key, value) when is_atom(key) do
    %{frame | assigns: Map.put(frame.assigns, key, value)}
  end

  @doc """
  Assigns a value to the frame only if the key doesn't already exist.

  The value is computed lazily using the provided function, which is only
  called if the key is not present in assigns.

  ## Examples

      # Only assigns if :timestamp doesn't exist
      frame = Frame.assign_new(frame, :timestamp, fn -> DateTime.utc_now() end)

      # Function is not called if key exists
      frame = frame |> Frame.assign(:count, 5)
                    |> Frame.assign_new(:count, fn -> expensive_computation() end)
      # count remains 5
  """
  @spec assign_new(t, key :: atom, value_fun :: (-> term)) :: t
  def assign_new(%__MODULE__{} = frame, key, fun) when is_atom(key) and is_function(fun, 0) do
    case frame.assigns do
      %{^key => _} -> frame
      _ -> assign(frame, key, fun.())
    end
  end

  @doc """
  Sets or updates private session data in the frame.

  Private data is used for framework-internal session context that persists
  across requests, similar to Plug.Conn.private.

  ## Examples

      # Set single private value
      frame = Frame.put_private(frame, :session_id, "abc123")

      # Set multiple private values
      frame = Frame.put_private(frame, %{
        session_id: "abc123",
        client_info: %{name: "my-client", version: "1.0.0"}
      })
  """
  @spec put_private(t, atom, any) :: t
  @spec put_private(t, Enumerable.t()) :: t
  def put_private(%__MODULE__{} = frame, key, value) when is_atom(key) do
    %{frame | private: Map.put(frame.private, key, value)}
  end

  def put_private(%__MODULE__{} = frame, private) when is_map(private) or is_list(private) do
    Enum.reduce(private, frame, fn {key, value}, frame -> put_private(frame, key, value) end)
  end

  @doc """
  Sets or updates transport data in the frame.

  Check `transport_t()` for reference.

  ## Examples

      # Set single transport value
      frame = Frame.put_transport(frame, :session_id, "abc123")

      # Set multiple transport values
      frame = Frame.put_transport(frame, %{
        session_id: "abc123",
        client_info: %{name: "my-client", version: "1.0.0"}
      })
  """
  @spec put_transport(t, atom, any) :: t
  @spec put_transport(t, Enumerable.t()) :: t
  def put_transport(%__MODULE__{} = frame, key, value) when is_atom(key) do
    %{frame | transport: Map.put(frame.transport, key, value)}
  end

  def put_transport(%__MODULE__{} = frame, transport) when is_map(transport) or is_list(transport) do
    Enum.reduce(transport, frame, fn {key, value}, frame -> put_transport(frame, key, value) end)
  end

  @doc """
  Sets the current request being processed.

  The request includes the request ID, method, and raw parameters before validation.

  ## Examples

      frame = Frame.put_request(frame, %{
        id: "req_123",
        method: "tools/call",
        params: %{"name" => "calculator", "arguments" => %{}}
      })
  """
  @spec put_request(t, map) :: t
  def put_request(%__MODULE__{} = frame, request) when is_map(request) do
    %{frame | request: request}
  end

  @doc """
  Clears the current request from the frame.

  This should be called after processing a request to ensure the frame doesn't
  retain stale request data.

  ## Examples

      frame = Frame.clear_request(frame)
  """
  @spec clear_request(t) :: t
  def clear_request(%__MODULE__{} = frame) do
    %{frame | request: nil}
  end

  @doc """
  Clears all session-specific private data from the frame.

  This should be called when a session ends to ensure the frame doesn't
  retain stale session data.

  ## Examples

      frame = Frame.clear_session(frame)
  """
  @spec clear_session(t) :: t
  def clear_session(%__MODULE__{} = frame) do
    %{frame | private: %{}}
  end

  @doc """
  Gets the MCP session ID from the frame's private data.

  ## Examples

      session_id = Frame.get_mcp_session_id(frame)
      # => "session_abc123"
  """
  @spec get_mcp_session_id(t) :: String.t() | nil
  def get_mcp_session_id(%__MODULE__{} = frame) do
    Map.get(frame.private, :session_id)
  end

  @doc """
  Gets the client info from the frame's private data.

  ## Examples

      client_info = Frame.get_client_info(frame)
      # => %{"name" => "my-client", "version" => "1.0.0"}
  """
  @spec get_client_info(t) :: map() | nil
  def get_client_info(%__MODULE__{} = frame) do
    Map.get(frame.private, :client_info)
  end

  @doc """
  Gets the client capabilities from the frame's private data.

  ## Examples

      capabilities = Frame.get_client_capabilities(frame)
      # => %{"tools" => %{}, "resources" => %{}}
  """
  @spec get_client_capabilities(t) :: map() | nil
  def get_client_capabilities(%__MODULE__{} = frame) do
    Map.get(frame.private, :client_capabilities)
  end

  @doc """
  Gets the protocol version from the frame's private data.

  ## Examples

      version = Frame.get_protocol_version(frame)
      # => "2025-03-26"
  """
  @spec get_protocol_version(t) :: String.t() | nil
  def get_protocol_version(%__MODULE__{} = frame) do
    Map.get(frame.private, :protocol_version)
  end

  @doc """
  Gets a request header value from HTTP transport.

  Returns the first value for the header, or nil if the transport
  is not HTTP or the header is not present.

  ## Examples

      # HTTP transport
      auth_header = Frame.get_req_header(frame, "authorization")
      # => "Bearer token123"

      # Non-HTTP transport or missing header
      auth_header = Frame.get_req_header(frame, "authorization")
      # => nil
  """
  @spec get_req_header(t, String.t()) :: String.t() | nil
  def get_req_header(%__MODULE__{transport: %{type: :http, req_headers: headers}}, name) when is_binary(name) do
    case List.keyfind(headers, String.downcase(name), 0) do
      {_, value} -> value
      nil -> nil
    end
  end

  def get_req_header(%__MODULE__{}, _name), do: nil

  @doc """
  Gets a query parameter value from HTTP transport.

  Returns the parameter value, or nil if the transport is not HTTP,
  query params weren't fetched, or the parameter doesn't exist.

  ## Examples

      # HTTP transport with query params
      session = Frame.get_query_param(frame, "session")
      # => "abc123"

      # Missing parameter or non-HTTP transport
      missing = Frame.get_query_param(frame, "nonexistent")
      # => nil
  """
  @spec get_query_param(t, String.t()) :: String.t() | nil
  def get_query_param(%__MODULE__{transport: %{type: :http, query_params: params}}, key)
      when is_map(params) and is_binary(key) do
    Map.get(params, key)
  end

  def get_query_param(%__MODULE__{}, _key), do: nil
end
