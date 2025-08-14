defmodule Hermes.Client.Operation do
  @moduledoc """
  Represents an operation to be performed by the MCP client.

  This struct encapsulates all information about a client API call:
  - `method` - The MCP method to call
  - `params` - The parameters to send to the server
  - `progress_opts` - Progress tracking options (optional)
  - `timeout` - The timeout for this specific operation (default: 30 seconds)
  """

  @default_timeout to_timeout(second: 30)

  @type progress_options :: [
          token: String.t() | integer(),
          callback: (String.t() | integer(), number(), number() | nil -> any())
        ]

  @type t :: %__MODULE__{
          method: String.t(),
          params: map(),
          progress_opts: progress_options() | nil,
          timeout: pos_integer(),
          headers: map() | nil
        }

  defstruct [
    :method,
    params: %{},
    progress_opts: [],
    timeout: @default_timeout,
    headers: nil
  ]

  @doc """
  Creates a new operation struct.

  ## Parameters

    * `attrs` - Map containing the operation attributes
      * `:method` - The MCP method name (required)
      * `:params` - The parameters to send to the server (required)
      * `:progress_opts` - Progress tracking options (optional)
      * `:timeout` - The timeout for this operation in milliseconds (optional, defaults to 30s)
      * `:headers` - HTTP headers to send with this request (optional, only for StreamableHTTP transport)
  """
  @spec new(%{
          required(:method) => String.t(),
          optional(:params) => map(),
          optional(:progress_opts) => progress_options() | nil,
          optional(:timeout) => pos_integer(),
          optional(:headers) => map()
        }) :: t()
  def new(%{method: method} = attrs) do
    %__MODULE__{
      method: method,
      params: Map.get(attrs, :params) || %{},
      progress_opts: Map.get(attrs, :progress_opts),
      timeout: Map.get(attrs, :timeout) || @default_timeout,
      headers: Map.get(attrs, :headers)
    }
  end
end
