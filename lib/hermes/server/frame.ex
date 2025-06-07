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

  @type t :: %__MODULE__{
          assigns: Enumerable.t(),
          initialized: boolean,
          private: %{
            optional(:session_id) => String.t(),
            optional(:client_info) => map(),
            optional(:client_capabilities) => map(),
            optional(:protocol_version) => String.t()
          },
          request:
            %{
              id: String.t(),
              method: String.t(),
              params: map()
            }
            | nil
        }

  defstruct assigns: %{}, initialized: false, private: %{}, request: nil

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
end
