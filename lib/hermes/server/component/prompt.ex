defmodule Hermes.Server.Component.Prompt do
  @moduledoc """
  Defines the behaviour for MCP prompts.

  Prompts are reusable templates that generate messages based on provided arguments.
  They help standardize common interactions and can be customized with parameters.

  ## Example

      defmodule MyServer.Prompts.CodeReview do
        @behaviour Hermes.Server.Behaviour.Prompt
        
        alias Hermes.Server.Frame
        
        @impl true
        def name, do: "code_review"
        
        @impl true
        def description do
          "Generate a code review prompt for the given programming language and code"
        end
        
        @impl true
        def arguments do
          [
            %{
              "name" => "language",
              "description" => "The programming language of the code",
              "required" => true
            },
            %{
              "name" => "code",
              "description" => "The code to review",
              "required" => true
            },
            %{
              "name" => "focus_areas",
              "description" => "Specific areas to focus on (e.g., performance, security)",
              "required" => false
            }
          ]
        end
        
        @impl true
        def get_messages(%{"language" => lang, "code" => code} = args, frame) do
          focus = Map.get(args, "focus_areas", "general quality")
          
          messages = [
            %{
              "role" => "user",
              "content" => %{
                "type" => "text",
                "text" => \"\"\"
                Please review the following \#{lang} code, focusing on \#{focus}:
                
                ```\#{lang}
                \#{code}
                ```
                
                Provide constructive feedback on:
                1. Code quality and readability
                2. Potential bugs or issues
                3. Performance considerations
                4. Best practices for \#{lang}
                \"\"\"
              }
            }
          ]
          
          # Can track prompt usage
          new_frame = Frame.assign(frame, :last_prompt_used, "code_review")
          
          {:ok, messages, new_frame}
        end
      end
  """

  alias Hermes.Server.Frame

  @type arguments :: map()
  @type message :: map()
  @type argument_def :: %{
          String.t() => String.t(),
          optional(String.t()) => boolean()
        }

  @doc """
  Returns the list of arguments this prompt accepts.

  Each argument should include:
  - `"name"` - The argument name
  - `"description"` - What the argument is for
  - `"required"` - Whether the argument is required (optional, defaults to false)

  ## Example

      [
        %{
          "name" => "topic",
          "description" => "The topic to generate content about",
          "required" => true
        },
        %{
          "name" => "tone",
          "description" => "The tone of voice (formal, casual, etc.)",
          "required" => false
        }
      ]
  """
  @callback arguments() :: [argument_def()]

  @doc """
  Generates messages based on the provided arguments.

  ## Parameters

  - `args` - The arguments provided by the client
  - `frame` - The server frame containing context and state

  ## Return Values

  - `{:ok, messages}` - Messages generated successfully, frame unchanged
  - `{:ok, messages, new_frame}` - Messages generated with frame updates
  - `{:error, reason}` - Failed to generate messages

  ## Message Format

  Messages should follow the MCP message format:

      %{
        "role" => "user" | "assistant",
        "content" => %{
          "type" => "text",
          "text" => "The message content"
        }
      }

  Multiple messages can be returned to create a conversation context.
  """
  @callback get_messages(args :: arguments(), frame :: Frame.t()) ::
              {:ok, messages :: [message()], new_frame :: Frame.t()}
              | {:error, reason :: String.t()}

  @doc """
  Converts a prompt module into the MCP protocol format.
  """
  @spec to_protocol(module()) :: map()
  def to_protocol(prompt_module) do
    %{
      "name" => prompt_module.name(),
      "description" => prompt_module.description(),
      "arguments" => prompt_module.arguments()
    }
  end

  @doc """
  Validates that a module implements the Prompt behaviour.
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
