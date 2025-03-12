defmodule Hermes.SSE do
  @moduledoc """
  Server-Sent Events (SSE) utilities, HTTP client abstraction and HTTP streaming handling.
  """

  alias Hermes.SSE.Parser

  require Logger

  @connection_headers %{
    "accept" => "text/event-stream",
    "cache-control" => "no-cache",
    "connection" => "keep-alive"
  }

  @default_http_opts [
    receive_timeout: :infinity,
    request_timeout: :infinity
  ]

  @doc """
  Connects to a server-sent event stream.

  ## Parameters

    - `server_url` - the URL of the server to connect to.
    - `headers` - additional headers to send with the request.
    - `opts` - additional options to pass to the HTTP client.

  ## Examples

      iex> Hermes.SSE.connect("http://localhost:4000")
      #Stream<[ref: 1, task: #PID<0.123.0>]>

  """
  @spec connect(String.t(), map(), Keyword.t()) :: Enumerable.t()
  def connect(server_url, headers \\ %{}, opts \\ []) do
    opts = Keyword.merge(@default_http_opts, opts)

    with {:ok, uri} <- parse_uri(server_url) do
      headers = Map.merge(headers, @connection_headers) |> Map.to_list()

      req = Finch.build(:get, uri, headers)
      ref = make_ref()
      task = spawn_stream_task(req, ref, opts)

      Stream.resource(fn -> {ref, task} end, &process_task_stream/1, &shutdown_task/1)
    end
  end

  defp parse_uri(url) do
    with {:error, _} <- URI.new(url), do: {:error, :invalid_url}
  end

  defp spawn_stream_task(%Finch.Request{} = req, ref, opts) do
    dest = Keyword.get(opts, :dest, self())

    Task.async(fn -> loop_sse_stream(req, ref, dest, opts) end)
  end

  defp loop_sse_stream(req, ref, dest, opts) do
    on_chunk = &process_sse_stream(&1, &2, dest, ref)

    case Finch.stream_while(req, Hermes.Finch, nil, on_chunk, opts) do
      {:ok, _} ->
        Logger.debug("SSE streaming closed with success, reconnecting...")
        loop_sse_stream(req, ref, dest, opts)

      {:error, err} ->
        Logger.error("SSE streaming closed with reason: #{inspect(err)}, reconnecting...")
        loop_sse_stream(req, ref, dest, opts)
    end
  end

  # the raw streaming response
  defp process_sse_stream({:status, status}, acc, _dest, _ref)
       when status != 200,
       do: {:halt, acc}

  defp process_sse_stream(chunk, acc, dest, ref) do
    send(dest, {:chunk, chunk, ref})
    {:cont, acc}
  end

  defp process_task_stream({ref, _task} = state) do
    receive do
      {:chunk, {:data, data}, ^ref} ->
        Logger.debug("Received sse streaming data chunk")
        {Parser.run(data), state}

      {:chunk, {:status, status}, ^ref} ->
        Logger.debug("Received sse streaming status #{status}")
        {[], state}

      {:chunk, {:headers, _headers}, ^ref} ->
        Logger.debug("Received sse streaming headers")
        {[], state}

      {:chunk, unknown, ^ref} ->
        Logger.debug("Received unknonw chunk: #{inspect(unknown)}")
        {[], state}
    end
  end

  defp shutdown_task({_ref, task}), do: Task.shutdown(task)
end
