if Code.ensure_loaded?(Plug) do
  defmodule Hermes.SSE.Streaming do
    @moduledoc false

    alias Hermes.Logging
    alias Hermes.SSE.Event

    require Hermes.Logging

    @type conn :: Plug.Conn.t()
    @type transport :: GenServer.server()
    @type session_id :: String.t()

    @doc """
    Starts the SSE streaming loop for a connection.

    This function takes control of the connection and enters a receive loop,
    streaming messages to the client as they arrive.

    ## Parameters
      - `conn` - The Plug.Conn that has been prepared for chunked response
      - `transport` - The transport process
      - `session_id` - The session identifier
      - `opts` - Options including:
        - `:initial_event_id` - Starting event ID (default: 0)
        - `:on_close` - Function to call when connection closes

    ## Messages handled
      - `{:sse_message, binary}` - Message to send to client
      - `:close_sse` - Close the connection gracefully
    """
    @spec start(conn, transport, session_id, keyword()) :: conn
    def start(conn, transport, session_id, opts \\ []) do
      initial_event_id = Keyword.get(opts, :initial_event_id, 0)
      on_close = Keyword.get(opts, :on_close, fn -> :ok end)

      try do
        loop(conn, transport, session_id, initial_event_id)
      after
        on_close.()
      end
    end

    @doc """
    Prepares a connection for SSE streaming.

    Sets appropriate headers and starts chunked response.
    """
    @spec prepare_connection(conn) :: conn
    def prepare_connection(conn) do
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("x-accel-buffering", "no")
      |> Plug.Conn.send_chunked(200)
    end

    @doc """
    Sends a single SSE event.

    This is useful for sending events outside of the main loop.
    """
    @spec send_event(conn, binary(), non_neg_integer()) ::
            {:ok, conn} | {:error, term()}
    def send_event(conn, data, event_id) when is_binary(data) do
      event = %Event{
        id: to_string(event_id),
        event: "message",
        data: data
      }

      case Plug.Conn.chunk(conn, Event.encode(event)) do
        {:ok, conn} -> {:ok, conn}
        {:error, reason} -> {:error, reason}
      end
    end

    # Private functions

    defp loop(conn, transport, session_id, event_counter) do
      receive do
        {:sse_message, message} when is_binary(message) ->
          case send_event(conn, message, event_counter) do
            {:ok, conn} ->
              loop(conn, transport, session_id, event_counter + 1)

            {:error, reason} ->
              Logging.transport_event(
                "sse_send_failed",
                %{
                  session_id: session_id,
                  reason: reason
                },
                level: :error
              )

              conn
          end

        :close_sse ->
          Logging.transport_event("sse_closing", %{session_id: session_id})
          Plug.Conn.halt(conn)

        {:plug_conn, :sent} ->
          # Ignore Plug internal messages
          loop(conn, transport, session_id, event_counter)

        msg ->
          Logging.transport_event(
            "sse_unknown_message",
            %{
              session_id: session_id,
              message: inspect(msg)
            },
            level: :warning
          )

          loop(conn, transport, session_id, event_counter)
      end
    end
  end
end
