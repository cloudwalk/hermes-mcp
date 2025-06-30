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

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame
  alias Hermes.Server.Response

  @type arguments :: map()
  @type message :: map()
  @type argument_def :: %{
          String.t() => String.t(),
          optional(String.t()) => boolean()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          arguments: map | nil,
          handler: module | nil,
          validate_input: (map -> {:ok, map} | {:error, [Peri.Error.t()]}) | nil
        }

  defstruct [
    :name,
    description: nil,
    arguments: nil,
    handler: nil,
    validate_input: nil
  ]

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
              {:reply, response :: Response.t(), new_state :: Frame.t()}
              | {:noreply, new_state :: Frame.t()}
              | {:error, error :: Error.t(), new_state :: Frame.t()}

  defimpl JSON.Encoder, for: __MODULE__ do
    alias Hermes.Server.Component.Prompt

    def encode(%Prompt{} = prompt, _) do
      prompt
      |> Map.take([:name, :description, :arguments])
      |> JSON.encode!()
    end
  end
end
