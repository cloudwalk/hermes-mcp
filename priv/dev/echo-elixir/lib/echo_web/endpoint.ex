defmodule EchoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :echo

  @session_options [
    store: :cookie,
    key: "_echo_key",
    signing_salt: "jggawrb5",
    same_site: "Lax"
  ]

  plug Plug.Static,
    at: "/",
    from: :echo,
    gzip: false,
    only: EchoWeb.static_paths()

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId, assign_as: :request_id
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EchoWeb.Router
end
