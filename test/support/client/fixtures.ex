defmodule Hermes.Client.Fixtures do
  @moduledoc """
  Fixtures for client tests.

  This module provides common response structures used in client tests to reduce duplication.
  """

  @doc """
  Returns a standard empty result response for a given request ID
  """
  def empty_result_response(request_id) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{}
    }
  end

  @doc """
  Returns a ping response for a given request ID
  """
  def ping_response(request_id) do
    empty_result_response(request_id)
  end

  @doc """
  Returns a resources/list response with optional resources and cursor
  """
  def resources_list_response(request_id, resources \\ [%{"name" => "test", "uri" => "test://uri"}], next_cursor \\ nil) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "resources" => resources,
        "nextCursor" => next_cursor
      }
    }
  end

  @doc """
  Returns a resources/read response for a given resource content
  """
  def resources_read_response(request_id, contents \\ [%{"text" => "resource content", "uri" => "test://uri"}]) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "contents" => contents
      }
    }
  end

  @doc """
  Returns a prompts/list response with optional prompts and cursor
  """
  def prompts_list_response(request_id, prompts \\ [%{"name" => "test_prompt"}], next_cursor \\ nil) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "prompts" => prompts,
        "nextCursor" => next_cursor
      }
    }
  end

  @doc """
  Returns a prompts/get response with the provided messages
  """
  def prompts_get_response(
        request_id,
        messages \\ [%{"role" => "user", "content" => %{"type" => "text", "text" => "Hello"}}]
      ) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "messages" => messages
      }
    }
  end

  @doc """
  Returns a tools/list response with optional tools and cursor
  """
  def tools_list_response(request_id, tools \\ [%{"name" => "test_tool"}], next_cursor \\ nil) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "tools" => tools,
        "nextCursor" => next_cursor
      }
    }
  end

  @doc """
  Returns a tools/call response with the provided content and error status
  """
  def tools_call_response(request_id, content \\ [%{"type" => "text", "text" => "Tool result"}], is_error \\ false) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "content" => content,
        "isError" => is_error
      }
    }
  end

  @doc """
  Returns a completion/complete response with the provided completion values
  """
  def completion_complete_response(request_id, values \\ ["python", "pytorch", "pyside"], total \\ 3, has_more \\ false) do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "result" => %{
        "completion" => %{
          "values" => values,
          "total" => total,
          "hasMore" => has_more
        }
      }
    }
  end

  @doc """
  Returns a standard error response for a given request ID
  """
  def error_response(request_id, code \\ -32_601, message \\ "Method not found") do
    %{
      "id" => request_id,
      "jsonrpc" => "2.0",
      "error" => %{
        "code" => code,
        "message" => message
      }
    }
  end

  @doc """
  Returns a cancelled notification for a given request ID
  """
  def cancelled_notification(request_id, reason \\ "server timeout") do
    %{
      "jsonrpc" => "2.0",
      "method" => "notifications/cancelled",
      "params" => %{
        "requestId" => request_id,
        "reason" => reason
      }
    }
  end

  @doc """
  Returns a progress notification for a given token
  """
  def progress_notification(progress_token, progress_value \\ 50, total_value \\ 100) do
    %{
      "method" => "notifications/progress",
      "params" => %{
        "progressToken" => progress_token,
        "progress" => progress_value,
        "total" => total_value
      }
    }
  end

  @doc """
  Returns a log notification 
  """
  def log_notification(level \\ "error", data \\ "Test error message", logger \\ "test-logger") do
    %{
      "jsonrpc" => "2.0",
      "method" => "notifications/message",
      "params" => %{
        "level" => level,
        "data" => data,
        "logger" => logger
      }
    }
  end
end
