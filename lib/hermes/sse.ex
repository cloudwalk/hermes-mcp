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
    with {:ok, uri} <- parse_uri(server_url) do
      headers = Map.merge(headers, @connection_headers) |> Map.to_list()

      req = Finch.build(:get, uri, headers)
      ref = make_ref()
      task = spawn_stream_task(req, ref, opts)

      Stream.resource(fn -> {ref, task} end, &process_stream/1, &shutdown_task/1)
    end
  end

  defp parse_uri(url) do
    with {:error, _} <- URI.new(url), do: {:error, :invalid_url}
  end

  defp spawn_stream_task(%Finch.Request{} = req, ref, opts) do
    dest = Keyword.get(opts, :dest, self())

    Task.async(fn ->
      on_chunk = fn chunk, acc ->
        send(dest, {:chunk, chunk, ref})
        {:cont, acc}
      end

      Finch.stream_while(req, Hermes.Finch, nil, on_chunk, opts)
    end)
  end

  defp process_stream({ref, _task} = state) do
    receive do
      {:chunk, {:data, data}, ^ref} -> {Parser.run(data), state}
      {:chunk, {:status, _status}, ^ref} -> {[], state}
      {:chunk, {:headers, _headers}, ^ref} -> {[], state}
    end
  end

  defp shutdown_task({_ref, task}), do: Task.shutdown(task)
end
