if Code.ensure_loaded?(Burrito) do
  defmodule Hermes.CLI do
    @moduledoc false

    alias Burrito.Util
    alias Mix.Interactive

    @doc """
    Main entry point for the standalone CLI application.
    """
    def main do
      args = Util.Args.argv()

      if Enum.join(args) =~ "help" do
        Interactive.CLI.show_help()
        System.halt(0)
      end

      Interactive.CLI.main(args)
    end
  end
end
