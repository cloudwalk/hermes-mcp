defmodule Hermes.Server.Component.Tool do
  @moduledoc """
  Defines the behaviour for MCP tools.

  Tools are functions that can be invoked by the client with specific parameters.
  Each tool must define its name, description, and parameter schema, as well as
  implement the execution logic.

  ## Example

      defmodule MyServer.Tools.Calculator do
        @behaviour Hermes.Server.Behaviour.Tool
        
        alias Hermes.Server.Frame
        
        @impl true
        def name, do: "calculator"
        
        @impl true
        def description, do: "Performs basic arithmetic operations"
        
        @impl true
        def input_schema do
          %{
            "type" => "object",
            "properties" => %{
              "operation" => %{
                "type" => "string",
                "enum" => ["add", "subtract", "multiply", "divide"]
              },
              "a" => %{"type" => "number"},
              "b" => %{"type" => "number"}
            },
            "required" => ["operation", "a", "b"]
          }
        end
        
        @impl true
        def execute(%{"operation" => "add", "a" => a, "b" => b}, frame) do
          result = a + b
          
          # Can access frame assigns
          user_id = frame.assigns[:user_id]
          
          # Can return updated frame if needed
          new_frame = Frame.assign(frame, :last_calculation, result)
          
          {:ok, result, new_frame}
        end
        
        @impl true
        def execute(%{"operation" => "divide", "a" => a, "b" => 0}, _frame) do
          {:error, "Cannot divide by zero"}
        end
      end
  """

  alias Hermes.Server.Frame

  @type params :: map()
  @type result :: term()
  @type schema :: map()

  @doc """
  Returns the unique name of the tool.

  This name is used by clients to invoke the tool.
  """
  @callback name() :: String.t()

  @doc """
  Returns a human-readable description of the tool.

  This should clearly explain what the tool does and when to use it.
  """
  @callback description() :: String.t()

  @doc """
  Returns the JSON Schema for the tool's input parameters.

  This schema is used to validate client requests and generate documentation.
  The schema should follow the JSON Schema specification.
  """
  @callback input_schema() :: schema()

  @doc """
  Executes the tool with the given parameters.

  ## Parameters

  - `params` - The validated input parameters from the client
  - `frame` - The server frame containing:
    - `assigns` - Custom data like session_id, client_info, user permissions
    - `initialized` - Whether the server has been initialized

  ## Return Values

  - `{:ok, result}` - Tool executed successfully, frame unchanged
  - `{:ok, result, new_frame}` - Tool executed successfully with frame updates
  - `{:error, reason}` - Tool failed with the given reason

  ## Frame Usage

  The frame provides access to server state and context:

      def execute(params, frame) do
        # Access assigns
        user_id = frame.assigns[:user_id]
        permissions = frame.assigns[:permissions]
        
        # Update frame if needed
        new_frame = Frame.assign(frame, :last_tool_call, DateTime.utc_now())
        
        {:ok, "Result", new_frame}
      end
  """
  @callback execute(params :: params(), frame :: Frame.t()) ::
              {:ok, result :: result()}
              | {:ok, result :: result(), new_frame :: Frame.t()}
              | {:error, reason :: String.t()}

  @doc """
  Converts a tool module into the MCP protocol format.
  """
  @spec to_protocol(module()) :: map()
  def to_protocol(tool_module) do
    %{
      "name" => tool_module.name(),
      "description" => tool_module.description(),
      "inputSchema" => tool_module.input_schema()
    }
  end

  @doc """
  Validates that a module implements the Tool behaviour.
  """
  @spec implements?(module()) :: boolean()
  def implements?(module) do
    behaviours =
      :attributes
      |> module.__info__()
      |> Keyword.get(:behaviour, [])
      |> List.flatten()

    __MODULE__ in behaviours
  end
end
