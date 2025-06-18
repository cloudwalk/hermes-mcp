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

  alias Hermes.MCP.Error
  alias Hermes.Server.Component
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @type params :: map()
  @type result :: term()
  @type schema :: map()
  @type annotations :: map() | nil

  @doc """
  Returns the JSON Schema for the tool's input parameters.

  This schema is used to validate client requests and generate documentation.
  The schema should follow the JSON Schema specification.
  """
  @callback input_schema() :: schema()

  @doc """
  Returns optional annotations for the tool.

  Annotations provide additional metadata about the tool that may be used
  by clients for enhanced functionality. This is an optional callback.

  ## Examples

      def annotations do
        %{
          "confidence" => 0.95,
          "category" => "text-processing",
          "tags" => ["nlp", "text"]
        }
      end
  """
  @callback annotations() :: annotations()
  @optional_callbacks annotations: 0

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
              {:reply, response :: Response.t(), new_state :: Frame.t()}
              | {:noreply, new_state :: Frame.t()}
              | {:error, error :: Error.t(), new_state :: Frame.t()}

  @doc """
  Converts a tool module into the MCP protocol format.

  ## Parameters
    * `tool_module` - The tool module
    * `name` - The tool name (optional, defaults to deriving from module name)
  """
  @spec to_protocol(module(), String.t() | nil) :: map()
  def to_protocol(tool_module, name \\ nil) do
    name = name || derive_tool_name(tool_module)

    base = %{
      "name" => name,
      "description" => Component.get_description(tool_module),
      "inputSchema" => tool_module.input_schema()
    }

    if Code.ensure_loaded?(tool_module) and function_exported?(tool_module, :annotations, 0) do
      Map.put(base, "annotations", tool_module.annotations())
    else
      base
    end
  end

  defp derive_tool_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
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
