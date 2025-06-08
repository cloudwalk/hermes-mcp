defmodule Hermes.MCP.Case do
  @moduledoc """
  Test case template for MCP protocol testing.

  Provides a consistent setup and common imports for MCP tests.
  """

  use ExUnit.CaseTemplate

  using opts do
    async = Keyword.get(opts, :async, false)

    quote do
      use ExUnit.Case, async: unquote(async)

      import Hermes.MCP.Assertions
      import Hermes.MCP.Builders
      import Hermes.MCP.Setup

      require Hermes.MCP.Message

      @moduletag capture_log: true
    end
  end
end
