defmodule MCPTest.Case do
  @moduledoc """
  Test case template for MCP protocol testing.

  Provides a consistent setup and common imports for MCP tests.
  Use this instead of ExUnit.Case for MCP-related tests.

  ## Usage

      defmodule MyMCPTest do
        use MCPTest.Case
        use Mimic

        
        test "my mcp test", %{client: client} do
          result = request_with_resources_response(client, [])
          assert_success(result)
        end
      end
      
      # For tests that need both client and server
      defmodule MyIntegrationTest do
        use MCPTest.Case, setup: [:client, :server]
        use Mimic

        
        test "integration test", %{client: client, server: server} do
          # Both client and server are available
        end
      end
  """

  use ExUnit.CaseTemplate

  using opts do
    async = Keyword.get(opts, :async, false)

    quote do
      use ExUnit.Case, async: unquote(async)

      import MCPTest.Assertions
      import MCPTest.Builders
      import MCPTest.Helpers
      import MCPTest.Setup

      alias Hermes.MCP.Error
      alias Hermes.MCP.Message

      @moduletag capture_log: true
    end
  end

  setup tags do
    ctx = %{}

    ctx = maybe_setup_client(ctx, tags)
    ctx = maybe_setup_server(ctx, tags)

    ctx
  end

  defp maybe_setup_client(ctx, %{client: true}) do
    MCPTest.Setup.initialized_client(ctx)
  end

  defp maybe_setup_client(ctx, %{client: opts}) when is_list(opts) do
    MCPTest.Setup.initialized_client(ctx, opts)
  end

  defp maybe_setup_client(ctx, _), do: ctx

  defp maybe_setup_server(ctx, %{server: true}) do
    MCPTest.Setup.initialized_server(ctx)
  end

  defp maybe_setup_server(ctx, %{server: opts}) when is_list(opts) do
    MCPTest.Setup.initialized_server(ctx, opts)
  end

  defp maybe_setup_server(ctx, _), do: ctx
end
