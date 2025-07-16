defmodule Hermes.HTTP do
  @moduledoc false

  use Hermes.Logging

  @default_headers %{
    "content-type" => "application/json"
  }

  def build(method, url, headers \\ %{}, body \\ nil, opts \\ []) do
    with {:ok, uri} <- parse_uri(url) do
      headers = Map.merge(@default_headers, headers)
      Finch.build(method, uri, Map.to_list(headers), body, opts)
    end
  end

  @doc """
  Performs a POST request to the given URL.
  """
  def post(url, headers \\ %{}, body \\ nil) do
    headers = Map.merge(@default_headers, headers)
    build(:post, url, headers, body)
  end

  defp parse_uri(url) do
    with {:error, _} <- URI.new(url), do: {:error, :invalid_url}
  end

  @max_redirects 3

  # @spec follow_redirect(Finch.Request.t(), non_neg_integer) ::
  #         {:ok, Finch.Response.t()} | {:error, term}
  def follow_redirect(%Finch.Request{} = request, attempts \\ @max_redirects) do
    with {:ok, resp} <- Finch.request(request, Hermes.Finch),
         do: do_follow_redirect(request, resp, attempts)
  end

  defp do_follow_redirect(_req, _resp, 0), do: {:error, :max_redirects}

  defp do_follow_redirect(req, %Finch.Response{status: 307, headers: headers}, attempts) when is_integer(attempts) do
    location = List.keyfind(headers, "location", 0)

    Hermes.Logging.transport_event("redirect", %{
      location: location,
      attempts_left: attempts,
      method: req.method
    })

    {:ok, uri} = URI.new(location)
    req = %{req | host: uri.host, port: uri.port, path: uri.path, scheme: uri.scheme}
    follow_redirect(req, max(0, attempts - 1))
  end

  defp do_follow_redirect(_req, %Finch.Response{} = resp, _attempts), do: {:ok, resp}
end
