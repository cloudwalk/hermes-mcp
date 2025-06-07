defmodule MCPTest.Builders do
  @moduledoc """
  Message builders for MCP protocol testing.

  Provides composable functions to build MCP messages with sensible defaults
  and optional overrides. Reduces boilerplate in test message construction.

  This module focuses on high-level test message builders and uses the core
  Hermes.MCP modules for actual encoding and error handling.
  """

  alias Hermes.MCP.Error
  alias Hermes.MCP.ID

  @default_protocol_version "2025-03-26"

  @doc """
  Builds an initialize request with default capabilities.

  ## Examples

      init_request()
      init_request(client_info: %{"name" => "MyClient"})
      init_request(capabilities: %{"custom" => %{}})
  """
  def init_request(opts \\ []) do
    capabilities = opts[:capabilities] || %{"roots" => %{}}
    client_info = opts[:client_info] || %{"name" => "TestClient", "version" => "1.0.0"}
    protocol_version = opts[:protocol_version] || @default_protocol_version

    %{
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => protocol_version,
        "capabilities" => capabilities,
        "clientInfo" => client_info
      }
    }
  end

  @doc """
  Builds an initialize response with default server capabilities.

  ## Examples

      init_response("request_123")
      init_response(123, server_capabilities: %{"tools" => %{}})
      init_response("req_1", server_info: %{"name" => "MyServer"})
  """
  def init_response(request_id, opts \\ []) do
    capabilities = opts[:server_capabilities] || default_server_capabilities()
    server_info = opts[:server_info] || default_server_info()
    protocol_version = opts[:protocol_version] || @default_protocol_version

    %{
      "result" => %{
        "protocolVersion" => protocol_version,
        "capabilities" => capabilities,
        "serverInfo" => server_info
      },
      "id" => request_id
    }
  end

  @doc """
  Builds an initialized notification.
  """
  def initialized_notification do
    %{"method" => "notifications/initialized", "params" => %{}}
  end

  # Resource Messages

  @doc """
  Builds a resources/list request.

  ## Examples

      resources_list_request()
      resources_list_request(cursor: "page_2")
  """
  def resources_list_request(opts \\ []) do
    params = %{}
    params = if cursor = opts[:cursor], do: Map.put(params, "cursor", cursor), else: params
    request_id = opts[:request_id] || ID.generate_request_id()

    build_request("resources/list", params, request_id: request_id)
  end

  @doc """
  Builds a resources/list response.

  ## Examples

      resources_list_response("req_1")
      resources_list_response(123, [%{"uri" => "test://res", "name" => "Test"}])
      resources_list_response("req_1", [], "next_page")
  """
  def resources_list_response(request_id, resources \\ [], next_cursor \\ nil) do
    result = %{"resources" => resources}
    result = if next_cursor, do: Map.put(result, "nextCursor", next_cursor), else: result

    build_response(request_id, result)
  end

  @doc """
  Builds a resources/read request.

  ## Examples

      resources_read_request("test://resource")
      resources_read_request("file://path", include_content: true)
  """
  def resources_read_request(uri, opts \\ []) do
    request_id = opts[:request_id] || ID.generate_request_id()
    params = %{"uri" => uri}

    build_request("resources/read", params, request_id: request_id)
  end

  @doc """
  Builds a resources/read response.

  ## Examples

      resources_read_response("req_1")
      resources_read_response(123, [%{"uri" => "test://res", "text" => "content"}])
  """
  def resources_read_response(request_id, contents \\ []) do
    contents = if contents == [], do: [%{"uri" => "test://uri", "text" => "resource content"}], else: contents

    build_response(request_id, %{"contents" => contents})
  end

  # Tool Messages

  @doc """
  Builds a tools/list request.
  """
  def tools_list_request(opts \\ []) do
    params = %{}
    params = if cursor = opts[:cursor], do: Map.put(params, "cursor", cursor), else: params

    build_request("tools/list", params)
  end

  @doc """
  Builds a tools/list response.

  ## Examples

      tools_list_response("req_1")
      tools_list_response(123, [%{"name" => "my_tool"}])
  """
  def tools_list_response(request_id, tools \\ [], next_cursor \\ nil) do
    tools = if tools == [], do: [%{"name" => "test_tool"}], else: tools
    result = %{"tools" => tools}
    result = if next_cursor, do: Map.put(result, "nextCursor", next_cursor), else: result

    build_response(request_id, result)
  end

  @doc """
  Builds a tools/call request.

  ## Examples

      tools_call_request("my_tool", %{"arg1" => "value"})
      tools_call_request("calc", %{"operation" => "add"}, progress_token: "token_123")
  """
  def tools_call_request(name, arguments \\ %{}, opts \\ []) do
    params = %{"name" => name, "arguments" => arguments}
    params = if token = opts[:progress_token], do: Map.put(params, "_meta", %{"progressToken" => token}), else: params

    build_request("tools/call", params)
  end

  @doc """
  Builds a tools/call response.

  ## Examples

      tools_call_response("req_1")
      tools_call_response(123, [%{"type" => "text", "text" => "result"}])
      tools_call_response("req_1", [], is_error: true)
  """
  def tools_call_response(request_id, content \\ [], opts \\ []) do
    content = if content == [], do: [%{"type" => "text", "text" => "Tool result"}], else: content
    is_error = opts[:is_error] || false

    build_response(request_id, %{
      "content" => content,
      "isError" => is_error
    })
  end

  # Prompt Messages

  @doc """
  Builds a prompts/list request.
  """
  def prompts_list_request(opts \\ []) do
    params = %{}
    params = if cursor = opts[:cursor], do: Map.put(params, "cursor", cursor), else: params

    build_request("prompts/list", params)
  end

  @doc """
  Builds a prompts/list response.
  """
  def prompts_list_response(request_id, prompts \\ [], next_cursor \\ nil) do
    prompts = if prompts == [], do: [%{"name" => "test_prompt"}], else: prompts
    result = %{"prompts" => prompts}
    result = if next_cursor, do: Map.put(result, "nextCursor", next_cursor), else: result

    build_response(request_id, result)
  end

  @doc """
  Builds a prompts/get request.
  """
  def prompts_get_request(name, arguments \\ %{}) do
    build_request("prompts/get", %{"name" => name, "arguments" => arguments})
  end

  @doc """
  Builds a prompts/get response.
  """
  def prompts_get_response(request_id, messages \\ []) do
    messages =
      if messages == [], do: [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}], else: messages

    build_response(request_id, %{"messages" => messages})
  end

  # Completion Messages

  @doc """
  Builds a completion/complete request.
  """
  def completion_complete_request(ref, argument \\ %{}) do
    build_request("completion/complete", %{"ref" => ref, "argument" => argument})
  end

  @doc """
  Builds a completion/complete response.
  """
  def completion_complete_response(request_id, values \\ [], opts \\ []) do
    values = if values == [], do: ["option1", "option2"], else: values
    total = opts[:total] || length(values)
    has_more = opts[:has_more] || false

    build_response(request_id, %{
      "completion" => %{
        "values" => values,
        "total" => total,
        "hasMore" => has_more
      }
    })
  end

  # Utility Messages

  @doc """
  Builds a ping request.
  """
  def ping_request do
    build_request("ping", %{})
  end

  @doc """
  Builds a ping response.
  """
  def ping_response(request_id) do
    build_response(request_id, %{})
  end

  @doc """
  Builds an empty result response.
  """
  def empty_result_response(request_id) do
    build_response(request_id, %{})
  end

  # Notification Messages

  @doc """
  Builds a cancelled notification.
  """
  def cancelled_notification(request_id, reason \\ "server timeout") do
    build_notification("notifications/cancelled", %{
      "requestId" => request_id,
      "reason" => reason
    })
  end

  @doc """
  Builds a progress notification.
  """
  def progress_notification(progress_token, progress \\ 50, total \\ 100) do
    build_notification("notifications/progress", %{
      "progressToken" => progress_token,
      "progress" => progress,
      "total" => total
    })
  end

  @doc """
  Builds a logging message notification.
  """
  def log_notification(level \\ "info", data \\ "Test message", logger \\ "test-logger") do
    build_notification("notifications/message", %{
      "level" => level,
      "data" => data,
      "logger" => logger
    })
  end

  # Error Builders

  @doc """
  Builds a generic error response.

  This is used when building custom errors in tests.
  """
  def error_response(request_id) do
    method_not_found_error(request_id)
  end

  @doc """
  Builds a parse error response.
  """
  def parse_error(request_id) do
    error = Error.protocol(:parse_error)
    build_error(request_id, error.code, "Parse error", error.data)
  end

  @doc """
  Builds an invalid request error response.
  """
  def invalid_request_error(request_id) do
    error = Error.protocol(:invalid_request)
    build_error(request_id, error.code, "Invalid Request", error.data)
  end

  @doc """
  Builds a method not found error response.
  """
  def method_not_found_error(request_id) do
    error = Error.protocol(:method_not_found)
    build_error(request_id, error.code, "Method not found", error.data)
  end

  @doc """
  Builds an invalid params error response.
  """
  def invalid_params_error(request_id) do
    error = Error.protocol(:invalid_params)
    build_error(request_id, error.code, "Invalid params", error.data)
  end

  @doc """
  Builds an internal error response.
  """
  def internal_error(request_id) do
    error = Error.protocol(:internal_error)
    build_error(request_id, error.code, "Internal error", error.data)
  end

  # Private Helpers

  defp default_server_capabilities do
    %{
      "resources" => %{},
      "tools" => %{},
      "prompts" => %{},
      "logging" => %{},
      "completion" => %{"complete" => true}
    }
  end

  defp default_server_info do
    %{
      "name" => "TestServer",
      "version" => "1.0.0"
    }
  end

  # Generic builder helpers that return message maps (not encoded strings)

  @doc false
  def build_request(method, params, opts \\ []) do
    request_id = opts[:request_id] || ID.generate_request_id()

    %{
      "method" => method,
      "params" => params,
      "id" => request_id
    }
  end

  @doc false
  def build_response(request_id, result) do
    %{
      "result" => result,
      "id" => request_id
    }
  end

  @doc false
  def build_notification(method, params) do
    %{
      "method" => method,
      "params" => params
    }
  end

  @doc false
  def build_error(request_id, code, message, data \\ %{}) do
    %{
      "error" => %{
        "code" => code,
        "message" => message,
        "data" => data
      },
      "id" => request_id
    }
  end
end
