defmodule Upcase.Main do
  @moduledoc """
  Main entry point for the Upcase server.
  """

  def main(_args \\ []) do
    Application.ensure_all_started(:upcase)

    # Keep the application running
    Process.sleep(:infinity)
  end
end
