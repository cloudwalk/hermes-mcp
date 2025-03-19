defmodule Hermes.CLI do
  @moduledoc """
  CLI entry point for the Hermes MCP standalone binary.

  This module serves as the main entry point when the application is built 
  as a standalone binary with Burrito. It delegates to the Mix.Interactive.CLI
  module for the actual CLI implementation.
  """

  alias Burrito.Util
  alias Mix.Interactive

  @doc """
  Main entry point for the standalone CLI application.
  """
  def main do
    args = Util.Args.argv()
    Interactive.CLI.main(args)
  end
end
