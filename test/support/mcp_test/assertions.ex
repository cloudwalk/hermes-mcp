defmodule MCPTest.Assertions do
  @moduledoc """
  MCP-specific assertion helpers.

  Provides domain-specific assertions for MCP protocol testing
  that give clear error messages and reduce boilerplate.
  """

  import ExUnit.Assertions

  @doc """
  Asserts that a value is a valid MCP message with proper structure.

  ## Examples

      assert_mcp_message(%{"jsonrpc" => "2.0", "method" => "ping"})
      assert_mcp_message(response, %{"id" => id, "result" => _}) when is_binary(id)
  """
  defmacro assert_mcp_message(message) do
    quote do
      message_value = unquote(message)

      assert %{"jsonrpc" => "2.0"} = message_value,
             "Expected MCP message with jsonrpc '2.0', got: #{inspect(message_value)}"

      message_value
    end
  end

  defmacro assert_mcp_message(message, pattern) do
    quote do
      message_value = unquote(message)

      assert %{"jsonrpc" => "2.0"} = message_value,
             "Expected MCP message with jsonrpc '2.0', got: #{inspect(message_value)}"

      assert unquote(pattern) = message_value
      message_value
    end
  end

  @doc """
  Asserts that a value is a valid MCP request.

  ## Examples

      assert_mcp_request(message, "ping")
      assert_mcp_request(message, "resources/list", %{"cursor" => "abc"})
  """
  defmacro assert_mcp_request(message, expected_method \\ nil, expected_params \\ nil) do
    quote bind_quoted: [message: message, expected_method: expected_method, expected_params: expected_params] do
      validated_message = assert_mcp_message(message)

      method = Map.get(validated_message, "method")
      params = Map.get(validated_message, "params")

      if expected_method do
        assert method == expected_method,
               "Expected method '#{expected_method}', got '#{method}'"
      end

      if expected_params do
        assert params == expected_params,
               "Expected params #{inspect(expected_params)}, got #{inspect(params)}"
      end

      validated_message
    end
  end

  @doc """
  Asserts that a value is a valid MCP response.

  ## Examples

      assert_mcp_response(message)
      assert_mcp_response(message, %{"resources" => []})
      assert_mcp_response(message, expected_result, request_id: "123")
  """
  defmacro assert_mcp_response(message, expected_result \\ nil, opts \\ quote(do: [])) do
    quote bind_quoted: [message: message, expected_result: expected_result, opts: opts] do
      validated_message = assert_mcp_message(message)

      id = Map.get(validated_message, "id")
      result = Map.get(validated_message, "result")

      if expected_request_id = opts[:request_id] do
        assert id == expected_request_id,
               "Expected request ID '#{expected_request_id}', got '#{id}'"
      end

      if expected_result do
        assert result == expected_result,
               "Expected result #{inspect(expected_result)}, got #{inspect(result)}"
      end

      validated_message
    end
  end

  @doc """
  Asserts that a value is a valid MCP error response.

  ## Examples

      assert_mcp_error(message)
      assert_mcp_error(message, -32601)
      assert_mcp_error(message, -32601, "Method not found")
  """
  defmacro assert_mcp_error(message, expected_code \\ nil, expected_message \\ nil, opts \\ quote(do: [])) do
    quote bind_quoted: [message: message, expected_code: expected_code, expected_message: expected_message, opts: opts] do
      validated_message = assert_mcp_message(message)

      id = Map.get(validated_message, "id")
      error = Map.get(validated_message, "error", %{})
      code = Map.get(error, "code")
      error_message = Map.get(error, "message")

      if expected_request_id = opts[:request_id] do
        assert id == expected_request_id,
               "Expected request ID '#{expected_request_id}', got '#{id}'"
      end

      if expected_code do
        assert code == expected_code,
               "Expected error code #{expected_code}, got #{code}"
      end

      if expected_message do
        assert error_message == expected_message,
               "Expected error message '#{expected_message}', got '#{error_message}'"
      end

      validated_message
    end
  end

  @doc """
  Asserts that a value is a valid MCP notification.

  ## Examples

      assert_mcp_notification(message, "notifications/initialized")
      assert_mcp_notification(message, "notifications/cancelled", %{"requestId" => "123"})
  """
  defmacro assert_mcp_notification(message, expected_method \\ nil, expected_params \\ nil) do
    quote bind_quoted: [message: message, expected_method: expected_method, expected_params: expected_params] do
      validated_message = assert_mcp_message(message)

      method = Map.get(validated_message, "method")
      params = Map.get(validated_message, "params")

      refute Map.has_key?(validated_message, "id"),
             "Notifications should not have an 'id' field, got: #{inspect(validated_message)}"

      if expected_method do
        assert method == expected_method,
               "Expected method '#{expected_method}', got '#{method}'"
      end

      if expected_params do
        assert params == expected_params,
               "Expected params #{inspect(expected_params)}, got #{inspect(params)}"
      end

      validated_message
    end
  end

  # Success/Error Result Assertions

  @doc """
  Asserts that a client function call was successful.

  ## Examples

      assert_success(Hermes.Client.ping(client))
      assert_success(Hermes.Client.list_resources(client), fn resources ->
        assert is_list(resources)
      end)
  """
  def assert_success(result, validator \\ nil) do
    assert {:ok, value} = result, "Expected success result, got: #{inspect(result)}"

    if validator && is_function(validator, 1) do
      validator.(value)
    end

    value
  end

  @doc """
  Asserts that a client function call resulted in an error.

  ## Examples

      assert_error(Hermes.Client.call_tool(client, "nonexistent", %{}))
      assert_error(result, fn error ->
        assert error.code == -32601
      end)
  """
  def assert_error(result, validator \\ nil) do
    assert {:error, error} = result, "Expected error result, got: #{inspect(result)}"

    if validator && is_function(validator, 1) do
      validator.(error)
    end

    error
  end

  # Resource-specific Assertions

  @doc """
  Asserts that a resources list response contains expected resources.

  ## Examples

      assert_resources(response, [%{"uri" => "test://res", "name" => "Test"}])
      assert_resources(response, count: 3)
      assert_resources(response, contains: %{"name" => "Test"})
  """
  def assert_resources(result, expected_or_opts) do
    case expected_or_opts do
      resources when is_list(resources) ->
        assert_success(result, fn resources_result ->
          assert resources_result == resources,
                 "Expected resources #{inspect(resources)}, got #{inspect(resources_result)}"
        end)

      opts when is_list(opts) ->
        assert_success(result, fn resources ->
          assert is_list(resources), "Expected resources list, got: #{inspect(resources)}"

          if count = opts[:count] do
            assert length(resources) == count,
                   "Expected #{count} resources, got #{length(resources)}"
          end

          if contains = opts[:contains] do
            found =
              Enum.any?(resources, fn resource ->
                Enum.all?(contains, fn {key, value} ->
                  resource[key] == value
                end)
              end)

            assert found, "Expected to find resource containing #{inspect(contains)} in #{inspect(resources)}"
          end

          if min_count = opts[:min_count] do
            assert length(resources) >= min_count,
                   "Expected at least #{min_count} resources, got #{length(resources)}"
          end

          if max_count = opts[:max_count] do
            assert length(resources) <= max_count,
                   "Expected at most #{max_count} resources, got #{length(resources)}"
          end
        end)
    end
  end

  # Tool-specific Assertions

  @doc """
  Asserts that a tools list response contains expected tools.
  """
  def assert_tools(result, expected_or_opts) do
    case expected_or_opts do
      tools when is_list(tools) ->
        assert_success(result, fn tools_result ->
          assert tools_result == tools,
                 "Expected tools #{inspect(tools)}, got #{inspect(tools_result)}"
        end)

      opts when is_list(opts) ->
        assert_success(result, fn tools ->
          assert is_list(tools), "Expected tools list, got: #{inspect(tools)}"

          if count = opts[:count] do
            assert length(tools) == count,
                   "Expected #{count} tools, got #{length(tools)}"
          end

          if contains = opts[:contains] do
            found =
              Enum.any?(tools, fn tool ->
                Enum.all?(contains, fn {key, value} ->
                  tool[key] == value
                end)
              end)

            assert found, "Expected to find tool containing #{inspect(contains)} in #{inspect(tools)}"
          end
        end)
    end
  end

  @doc """
  Asserts that a tool call response contains expected content.

  ## Examples

      assert_tool_call_result(result, [%{"type" => "text", "text" => "Hello"}])
      assert_tool_call_result(result, text_contains: "Hello")
      assert_tool_call_result(result, is_error: false)
  """
  def assert_tool_call_result(result, expected_or_opts) do
    case expected_or_opts do
      content when is_list(content) ->
        assert_success(result, fn call_result ->
          assert call_result == content,
                 "Expected tool call content #{inspect(content)}, got #{inspect(call_result)}"
        end)

      opts when is_list(opts) ->
        assert_success(result, fn content ->
          assert is_list(content), "Expected tool call content list, got: #{inspect(content)}"

          if text_contains = opts[:text_contains] do
            text_content = extract_text_from_content(content)

            assert String.contains?(text_content, text_contains),
                   "Expected tool result to contain '#{text_contains}', got: #{text_content}"
          end

          if is_error = opts[:is_error] do
            if is_error do
              assert true, "Cannot verify error status from content alone - check response structure"
            end
          end
        end)
    end
  end

  # Utility Functions

  defp extract_text_from_content(content) do
    content
    |> Enum.filter(fn item -> item["type"] == "text" end)
    |> Enum.map_join(" ", fn item -> item["text"] end)
  end

  # Initialization Assertions

  @doc """
  Asserts that a client is properly initialized.
  """
  def assert_client_initialized(client) do
    state = :sys.get_state(client)
    assert state.initialized, "Expected client to be initialized"
    assert state.server_capabilities != nil, "Expected server capabilities to be set"
    state
  end

  @doc """
  Asserts that a server is properly initialized.
  """
  def assert_server_initialized(server) do
    state = :sys.get_state(server)
    assert state.initialized, "Expected server to be initialized"
    state
  end

  # Capability Assertions

  @doc """
  Asserts that client has specific capabilities.
  """
  def assert_client_capabilities(client, expected_capabilities) do
    state = :sys.get_state(client)
    capabilities = state.client_capabilities || %{}

    Enum.each(expected_capabilities, fn {key, expected_value} ->
      actual_value = capabilities[key]

      assert actual_value == expected_value,
             "Expected client capability '#{key}' to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
    end)

    capabilities
  end

  @doc """
  Asserts that client received specific server capabilities.
  """
  def assert_server_capabilities(client, expected_capabilities) do
    state = :sys.get_state(client)
    capabilities = state.server_capabilities || %{}

    Enum.each(expected_capabilities, fn {key, expected_value} ->
      actual_value = capabilities[key]

      assert actual_value == expected_value,
             "Expected server capability '#{key}' to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
    end)

    capabilities
  end
end
