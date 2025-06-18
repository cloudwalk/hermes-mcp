defmodule Incomer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_, _) do
    children = [
      {Incomer.Client, transport: {:streamable_http, base_url: "http://localhost:4000"}}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Incomer.Supervisor)
  end
end
