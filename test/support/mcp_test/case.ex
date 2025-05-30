defmodule MCPTest.Case do
  @moduledoc """
  Test case template for MCP protocol testing.

  Provides a consistent setup and common imports for MCP tests.
  Use this instead of ExUnit.Case for MCP-related tests.

  ## Usage

      defmodule MyMCPTest do
        use MCPTest.Case
        use Mimic

        # Explicit mocking setup
        Mimic.copy(Hermes.MockTransport)
        setup :verify_on_exit!
        
        test "my mcp test", %{client: client} do
          result = request_with_resources_response(client, [])
          assert_success(result)
        end
      end
      
      # For tests that need both client and server
      defmodule MyIntegrationTest do
        use MCPTest.Case, setup: [:client, :server]
        use Mimic

        # Explicit mocking setup
        Mimic.copy(Hermes.MockTransport)
        setup :verify_on_exit!
        
        test "integration test", %{client: client, server: server} do
          # Both client and server are available
        end
      end
  """

  use ExUnit.CaseTemplate

  using opts do
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)
      use MCPTest

      @moduletag capture_log: true
    end
  end

  setup tags do
    ctx = %{}

    ctx = maybe_setup_client(ctx, tags)
    ctx = maybe_setup_server(ctx, tags)

    ctx
  end

  # Setup Functions

  # Tag-based setup
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
