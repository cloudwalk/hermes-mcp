defmodule Hermes.Server.Frame do
  @moduledoc """
  The Hermes Frame.

  This module defines a struct and functions for working with
  MCP server state throughout the request/response lifecycle.

  ## User fields

  These fields contain user-controlled data:

    * `assigns` - shared user data as a map. For HTTP transports, this inherits
      from `Plug.Conn.assigns`. Users are responsible for populating authentication
      data through their Plug pipeline before it reaches the MCP server.

  ## Transport fields

  These fields contain transport-specific context. The structure varies by transport type:

  ### HTTP transport (when `transport.type == :http`)

    * `req_headers` - the request headers as a list, example: `[{"content-type", "application/json"}]`.
      All header names are downcased.
    * `query_params` - the request query params as a map, example: `%{"session" => "abc123"}`.
      Returns `nil` if query params were not fetched by the Plug pipeline.
    * `remote_ip` - the IP of the client, example: `{151, 236, 219, 228}`. 
      This field is set by the transport layer.
    * `scheme` - the request scheme as an atom, example: `:https`
    * `host` - the requested host as a binary, example: `"api.example.com"`
    * `port` - the requested port as an integer, example: `443`
    * `request_path` - the requested path, example: `"/mcp"`

  ### STDIO transport (when `transport.type == :stdio`)

    * `env` - environment variables as a map, example: `%{"USER" => "alice", "HOME" => "/home/alice"}`
    * `pid` - the OS process ID as a string, example: `"12345"`

  ## MCP protocol fields

  These fields contain MCP-specific data:

    * `request` - the current MCP request being processed, with fields:
      * `id` - the request ID for correlation
      * `method` - the MCP method being called, example: `"tools/call"`
      * `params` - the raw request parameters (before validation)
    * `initialized` - boolean indicating if the MCP session has been initialized

  ## Private fields

  These fields are reserved for framework usage:

    * `private` - shared framework data as a map. Contains MCP session context:
      * `session_id` - unique identifier for the current client session being handled
      * `client_info` - client information from initialization, example: `%{"name" => "my-client", "version" => "1.0.0"}`
      * `client_capabilities` - negotiated client capabilities
      * `protocol_version` - active MCP protocol version, example: `"2025-03-26"`
  """

  alias Hermes.Server.Component
  alias Hermes.Server.Component.Prompt
  alias Hermes.Server.Component.Resource
  alias Hermes.Server.Component.Schema
  alias Hermes.Server.Component.Tool

  @type server_component_t :: Tool.t() | Resource.t() | Prompt.t()

  @type private_t :: %{
          optional(:session_id) => String.t(),
          optional(:client_info) => map(),
          optional(:client_capabilities) => map(),
          optional(:protocol_version) => String.t(),
          optional(:server_module) => module(),
          optional(:server_registry) => module(),
          optional(:pagination_limit) => non_neg_integer(),
          optional(:__mcp_components__) => list(server_component_t)
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

  defstruct assigns: %{},
            initialized: false,
            private: %{},
            request: nil,
            transport: %{}

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
    Enum.reduce(assigns, frame, fn {key, value}, frame ->
      assign(frame, key, value)
    end)
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
    Enum.reduce(private, frame, fn {key, value}, frame ->
      put_private(frame, key, value)
    end)
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
    Enum.reduce(transport, frame, fn {key, value}, frame ->
      put_transport(frame, key, value)
    end)
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
  Sets the pagination limit for listing operations.

  This limit is used by handlers when returning lists of tools, prompts, or resources
  to control the maximum number of items returned in a single response. When the limit
  is set and the total number of items exceeds it, the response will include a
  `nextCursor` field for pagination.

  ## Examples

      # Set pagination limit to 10 items per page
      frame = Frame.put_pagination_limit(frame, 10)

      # The limit is stored in private data
      frame.private.pagination_limit
      # => 10
  """
  @spec put_pagination_limit(t, non_neg_integer) :: t
  def put_pagination_limit(%__MODULE__{} = frame, limit) when limit > 0 do
    put_private(frame, %{pagination_limit: limit})
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

  @doc """
  Registers a tool definition.
  """
  @spec register_tool(t, String.t(), list(tool_opt)) :: t
        when tool_opt:
               {:description, String.t() | nil}
               | {:input_schema, map | nil}
               | {:output_schema, map | nil}
               | {:title, String.t() | nil}
               | {:annotations, map | nil}
  def register_tool(%__MODULE__{} = frame, name, opts) when is_binary(name) do
    input_schema = Schema.normalize(opts[:input_schema] || %{})
    raw_schema = Component.__clean_schema_for_peri__(input_schema)
    validate_input = fn params -> Peri.validate(raw_schema, params) end

    output_schema = if s = opts[:output_schema], do: Schema.normalize(s)

    validate_output =
      if output_schema do
        raw_output = Component.__clean_schema_for_peri__(output_schema)
        fn params -> Peri.validate(raw_output, params) end
      end

    update_components(frame, %Tool{
      name: name,
      description: opts[:description],
      input_schema: Schema.to_json_schema(input_schema),
      output_schema: if(output_schema, do: Schema.to_json_schema(output_schema)),
      annotations: opts[:annotations],
      validate_input: validate_input,
      validate_output: validate_output
    })
  end

  @doc """
  Registers a prompt definition.
  """
  @spec register_prompt(t, String.t(), list(prompt_opt)) :: t
        when prompt_opt: {:description, String.t() | nil} | {:arguments, map | nil}
  def register_prompt(%__MODULE__{} = frame, name, opts) when is_binary(name) do
    arguments = Schema.normalize(opts[:arguments] || %{})
    raw_schema = Component.__clean_schema_for_peri__(arguments)
    validate_input = fn params -> Peri.validate(raw_schema, params) end

    update_components(frame, %Prompt{
      name: name,
      description: opts[:description],
      arguments: Schema.to_prompt_arguments(arguments),
      validate_input: validate_input
    })
  end

  @doc """
  Registers a resource definition. THis also supports resource templates (via URI templates).
  """
  @spec register_resource(t, String.t(), list(resource_opt)) :: t
        when resource_opt:
               {:title, String.t() | nil}
               | {:name, String.t() | nil}
               | {:description, String.t() | nil}
               | {:mime_type, String.t() | nil}
  def register_resource(%__MODULE__{} = frame, uri, opts) when is_binary(uri) do
    update_components(frame, %Resource{
      uri: uri,
      title: opts[:title],
      name: opts[:name] || uri,
      description: opts[:description],
      mime_type: opts[:mime_type] || "text/plain"
    })
  end

  @doc "Clears all current registered components (tools, resources, prompts)"
  @spec clear_components(t) :: t
  def clear_components(%__MODULE__{} = frame) do
    put_in(frame, [Access.key!(:private), :__mcp_components__], [])
  end

  @doc "Retrieves all current registered components (tools, resources, prompts)"
  @spec get_components(t) :: list(server_component_t)
  def get_components(%__MODULE__{} = frame) do
    Map.get(frame.private, :__mcp_components__, [])
  end

  @doc false
  @spec get_tools(t) :: list(Tool.t())
  def get_tools(%__MODULE__{} = frame) do
    frame
    |> get_components()
    |> Enum.filter(&match?(%Tool{}, &1))
  end

  @doc false
  @spec get_prompts(t) :: list(Prompt.t())
  def get_prompts(%__MODULE__{} = frame) do
    frame
    |> get_components()
    |> Enum.filter(&match?(%Prompt{}, &1))
  end

  @doc false
  @spec get_resources(t) :: list(Resource.t())
  def get_resources(%__MODULE__{} = frame) do
    frame
    |> get_components()
    |> Enum.filter(&match?(%Resource{}, &1))
  end

  @doc false
  @spec get_component(t, name :: String.t()) :: server_component_t | nil
  def get_component(%__MODULE__{} = frame, name) do
    frame
    |> get_components()
    |> Enum.find(&(&1.name == name))
  end

  # Private helpers

  defp update_components(frame, component) do
    components = [component | get_components(frame)]
    put_private(frame, :__mcp_components__, Enum.uniq_by(components, &unique_component/1))
  end

  defp unique_component(%struct{name: name}) do
    {struct, name}
  end
end

defimpl Inspect, for: Hermes.Server.Frame do
  import Inspect.Algebra

  def inspect(frame, opts) do
    components = frame.private[:__mcp_components__] || []
    tools_count = Enum.count(components, &match?(%Hermes.Server.Component.Tool{}, &1))

    resources_count =
      Enum.count(components, &match?(%Hermes.Server.Component.Resource{}, &1))

    prompts_count = Enum.count(components, &match?(%Hermes.Server.Component.Prompt{}, &1))

    info = [
      assigns: frame.assigns,
      initialized: frame.initialized,
      tools: tools_count,
      resources: resources_count,
      prompts: prompts_count
    ]

    info = if frame.request, do: [{:request, frame.request.method} | info], else: info

    info =
      if session_id = frame.private[:session_id],
        do: [{:session_id, session_id} | info],
        else: info

    concat(["#Frame<", to_doc(info, opts), ">"])
  end
end
