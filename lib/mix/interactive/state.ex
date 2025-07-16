defmodule Mix.Interactive.State do
  @moduledoc false

  alias Hermes.Client.Request
  alias Hermes.Transport.SSE
  alias Hermes.Transport.STDIO
  alias Hermes.Transport.StreamableHTTP
  alias Mix.Interactive.UI

  @doc """
  Prints the formatted state of the client and its associated transport.

  ## Parameters

    * `client` - The client process to inspect
  """
  @spec print_state(GenServer.server()) :: :ok
  def print_state(client) do
    client_state = :sys.get_state(client)
    transport = get_transport_info(client_state)
    verbose = System.get_env("HERMES_VERBOSE") == "1"

    print_client_state(client, client_state, verbose)
    print_transport_state(transport.pid, transport.layer, verbose)
  end

  defp get_transport_info(client_state) do
    transport_info = client_state.transport

    layer =
      if is_map(transport_info), do: transport_info[:layer], else: transport_info

    transport_pid =
      if is_map(transport_info) and Map.has_key?(transport_info, :name) and
           is_pid(transport_info.name) do
        transport_info.name
      else
        Process.whereis(layer)
      end

    %{layer: layer, pid: transport_pid}
  end

  defp print_client_state(client, state, verbose) do
    IO.puts("\n#{UI.colors().success}Client State (#{inspect(client)}):#{UI.colors().reset}")

    print_protocol_info(state)
    print_client_info(state, verbose)
    print_server_capabilities(state, verbose)
    print_server_info(state, verbose)
    print_pending_requests(state.pending_requests, verbose)

    if verbose do
      print_callbacks_info(state)
    end
  end

  defp print_protocol_info(state) do
    IO.puts("  #{UI.colors().info}Protocol Version:#{UI.colors().reset} #{state.protocol_version}")
  end

  defp print_client_info(state, _verbose) do
    IO.puts("  #{UI.colors().info}Client Info:#{UI.colors().reset}")
    print_map(state.client_info, 4)
  end

  defp print_server_capabilities(state, verbose) do
    if state.server_capabilities do
      IO.puts("  #{UI.colors().info}Server Capabilities:#{UI.colors().reset}")

      if verbose do
        # Show full details in verbose mode
        print_map(state.server_capabilities, 4)
      else
        # Show summary in normal mode
        capability_keys = Map.keys(state.server_capabilities)
        IO.puts("    #{inspect(capability_keys)}")
      end
    else
      IO.puts("  #{UI.colors().warning}Server Capabilities: Not yet established#{UI.colors().reset}")
    end
  end

  defp print_server_info(state, _verbose) do
    if state.server_info do
      IO.puts("  #{UI.colors().info}Server Info:#{UI.colors().reset}")
      print_map(state.server_info, 4)
    else
      IO.puts("  #{UI.colors().warning}Server Info: Not yet established#{UI.colors().reset}")
    end
  end

  defp print_pending_requests(pending_requests, verbose) do
    request_count = map_size(pending_requests)

    if request_count == 0 do
      IO.puts("  #{UI.colors().info}Pending Requests:#{UI.colors().reset} None")
    else
      IO.puts("  #{UI.colors().info}Pending Requests (#{request_count}):#{UI.colors().reset}")

      Enum.each(pending_requests, &print_request(&1, verbose))
    end
  end

  defp print_request({id, request}, verbose) do
    elapsed_ms = Request.elapsed_time(request)

    IO.puts("    #{UI.colors().command}#{id}#{UI.colors().reset} - Method: #{request.method}, Elapsed: #{elapsed_ms}ms")

    if verbose do
      print_request_details(request)
    end
  end

  defp print_request_details(request) do
    IO.puts("      Started at: #{inspect(request.start_time)}")
    IO.puts("      From: #{inspect(request.from)}")
  end

  defp print_callbacks_info(state) do
    IO.puts("  #{UI.colors().info}Callbacks:#{UI.colors().reset}")

    # Progress callbacks
    progress_count = map_size(state.progress_callbacks)

    if progress_count > 0 do
      IO.puts("    #{UI.colors().info}Progress Callbacks (#{progress_count}):#{UI.colors().reset}")

      Enum.each(state.progress_callbacks, fn {token, _callback} ->
        IO.puts("      #{UI.colors().command}#{token}#{UI.colors().reset}")
      end)
    else
      IO.puts("    #{UI.colors().info}Progress Callbacks:#{UI.colors().reset} None")
    end

    # Log callback
    if state.log_callback do
      IO.puts("    #{UI.colors().info}Log Callback:#{UI.colors().reset} Configured")
    else
      IO.puts("    #{UI.colors().info}Log Callback:#{UI.colors().reset} None")
    end
  end

  defp print_transport_state(nil, transport_layer, _verbose) do
    IO.puts(
      "\n#{UI.colors().error}Transport State (#{inspect(transport_layer)}):#{UI.colors().reset} Not available (process not found)"
    )
  end

  defp print_transport_state(transport_pid, transport_layer, verbose) when is_pid(transport_pid) do
    if Process.alive?(transport_pid) do
      transport_state = :sys.get_state(transport_pid)

      case transport_layer do
        SSE ->
          print_sse_transport_state(transport_pid, transport_state, verbose)

        STDIO ->
          print_stdio_transport_state(transport_pid, transport_state, verbose)

        StreamableHTTP ->
          print_streamable_http_transport_state(
            transport_pid,
            transport_state,
            verbose
          )

        _ ->
          print_unknown_transport_state(transport_pid, transport_state, verbose)
      end
    else
      IO.puts(
        "\n#{UI.colors().error}Transport State (#{inspect(transport_layer)}):#{UI.colors().reset} Not available (process not running)"
      )
    end
  end

  defp print_transport_state(_transport_pid, transport_layer, _verbose) do
    IO.puts(
      "\n#{UI.colors().error}Transport State (#{inspect(transport_layer)}):#{UI.colors().reset} Not available (invalid process identifier)"
    )
  end

  defp print_sse_transport_state(pid, state, verbose) do
    IO.puts("\n#{UI.colors().success}SSE Transport State (#{inspect(pid)}):#{UI.colors().reset}")

    IO.puts("  #{UI.colors().info}Server URL:#{UI.colors().reset} #{state[:server_url]}")

    IO.puts("  #{UI.colors().info}SSE URL:#{UI.colors().reset} #{state[:sse_url]}")

    print_sse_connection_status(state)
    print_sse_stream_task(state)

    if verbose do
      # Print additional transport details in verbose mode
      if map_size(state[:headers] || %{}) > 0 do
        IO.puts("  #{UI.colors().info}Headers:#{UI.colors().reset}")
        print_map(state[:headers], 4)
      end

      if state[:transport_opts] do
        IO.puts("  #{UI.colors().info}Transport Options:#{UI.colors().reset} #{inspect(state[:transport_opts])}")
      end

      if state[:http_options] do
        IO.puts("  #{UI.colors().info}HTTP Options:#{UI.colors().reset} #{inspect(state[:http_options])}")
      end
    end
  end

  defp print_sse_connection_status(state) do
    if state[:message_url] do
      IO.puts("  #{UI.colors().info}Message URL:#{UI.colors().reset} #{state[:message_url]}")

      IO.puts("  #{UI.colors().success}Status:#{UI.colors().reset} Connected")
    else
      IO.puts("  #{UI.colors().warning}Status:#{UI.colors().reset} Connecting/Not connected")
    end
  end

  defp print_sse_stream_task(state) do
    if state[:stream_task] do
      task = state[:stream_task]
      status = if Process.alive?(task.pid), do: "alive", else: "dead"

      IO.puts("  #{UI.colors().info}Stream Task:#{UI.colors().reset} #{inspect(task.pid)} (#{status})")
    end
  end

  defp print_stdio_transport_state(pid, state, verbose) do
    IO.puts("\n#{UI.colors().success}STDIO Transport State (#{inspect(pid)}):#{UI.colors().reset}")

    IO.puts("  #{UI.colors().info}Command:#{UI.colors().reset} #{state.command}")

    print_stdio_args(state)
    print_stdio_connection_status(state)

    if verbose do
      # Print additional transport details in verbose mode
      if state.cwd do
        IO.puts("  #{UI.colors().info}Working Directory:#{UI.colors().reset} #{state.cwd}")
      end

      if state.env do
        IO.puts("  #{UI.colors().info}Environment:#{UI.colors().reset}")
        print_map(state.env, 4)
      end
    end
  end

  defp print_stdio_args(state) do
    if state.args do
      IO.puts("  #{UI.colors().info}Args:#{UI.colors().reset} #{inspect(state.args)}")
    end
  end

  defp print_stdio_connection_status(state) do
    if state.port do
      status = if Port.info(state.port), do: "open", else: "closed"

      IO.puts("  #{UI.colors().info}Port:#{UI.colors().reset} #{inspect(state.port)} (#{status})")

      IO.puts("  #{UI.colors().success}Status:#{UI.colors().reset} Connected")
    else
      IO.puts("  #{UI.colors().warning}Status:#{UI.colors().reset} Not connected")
    end
  end

  defp print_streamable_http_transport_state(pid, state, verbose) do
    IO.puts("\n#{UI.colors().success}Streamable HTTP Transport State (#{inspect(pid)}):#{UI.colors().reset}")

    IO.puts("  #{UI.colors().info}MCP URL:#{UI.colors().reset} #{URI.to_string(state.mcp_url)}")

    print_streamable_http_session_status(state)

    if verbose do
      # Print additional transport details in verbose mode
      if map_size(state.headers || %{}) > 0 do
        IO.puts("  #{UI.colors().info}Headers:#{UI.colors().reset}")
        print_map(state.headers, 4)
      end

      if state.transport_opts != [] do
        IO.puts("  #{UI.colors().info}Transport Options:#{UI.colors().reset} #{inspect(state.transport_opts)}")
      end

      if state.http_options do
        IO.puts("  #{UI.colors().info}HTTP Options:#{UI.colors().reset} #{inspect(state.http_options)}")
      end
    end
  end

  defp print_streamable_http_session_status(state) do
    if state.session_id do
      IO.puts("  #{UI.colors().info}Session ID:#{UI.colors().reset} #{state.session_id}")

      IO.puts("  #{UI.colors().success}Status:#{UI.colors().reset} Connected with session")
    else
      IO.puts("  #{UI.colors().info}Status:#{UI.colors().reset} Connected (no session)")
    end

    IO.puts("  #{UI.colors().info}Client:#{UI.colors().reset} #{inspect(state.client)}")
  end

  defp print_unknown_transport_state(pid, state, verbose) do
    IO.puts("\n#{UI.colors().success}Unknown Transport State (#{inspect(pid)}):#{UI.colors().reset}")

    if verbose do
      # In verbose mode, show the full state with pretty printing
      IO.puts("  #{inspect(state, pretty: true, limit: 50)}")
    else
      # In normal mode, show a summary
      IO.puts("  #{inspect(state, pretty: true, limit: 5)}")
    end
  end

  defp print_map(map, indent_level) when is_map(map) do
    Enum.each(map, fn {key, value} ->
      print_map_entry(key, value, indent_level)
    end)
  end

  defp print_map_entry(key, value, indent_level) do
    indent = String.duplicate(" ", indent_level)

    cond do
      is_map(value) and map_size(value) > 0 ->
        IO.puts("#{indent}#{UI.colors().command}#{key}:#{UI.colors().reset}")
        print_map(value, indent_level + 2)

      is_list(value) and value != [] ->
        IO.puts("#{indent}#{UI.colors().command}#{key}:#{UI.colors().reset}")
        print_list(value, indent_level + 2)

      true ->
        IO.puts("#{indent}#{UI.colors().command}#{key}:#{UI.colors().reset} #{inspect(value)}")
    end
  end

  defp print_list(list, indent_level) do
    indent = String.duplicate(" ", indent_level)

    Enum.each(list, fn item ->
      cond do
        is_map(item) and map_size(item) > 0 ->
          IO.puts("#{indent}-")
          print_map(item, indent_level + 2)

        is_list(item) and item != [] ->
          IO.puts("#{indent}- [...]")
          print_list(item, indent_level + 2)

        true ->
          IO.puts("#{indent}- #{inspect(item)}")
      end
    end)
  end
end
