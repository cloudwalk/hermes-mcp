defmodule MCPTest do
  @moduledoc """
  Test helpers for MCP protocol testing.

  Provides a collection of helper functions to reduce boilerplate
  and make MCP protocol tests more maintainable.

  ## Usage

      defmodule MyTest do
        use ExUnit.Case
        import MCPTest
        
        test "my test" do
          client = setup_client()
          # Use helpers...
        end
      end
  """

  @doc """
  Imports all MCPTest helper modules and core MCP modules.
  """
  defmacro __using__(_opts) do
    quote do
      import MCPTest.Assertions
      import MCPTest.Builders
      import MCPTest.Helpers
      import MCPTest.Setup

      alias Hermes.MCP.Error
      alias Hermes.MCP.Message
    end
  end
end
