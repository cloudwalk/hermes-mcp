defmodule Hermes.Server.ComponentPromptTest do
  use ExUnit.Case, async: true

  alias TestPrompts.FieldPrompt
  alias TestPrompts.LegacyPrompt
  alias TestPrompts.NestedPrompt

  describe "prompt with field metadata" do
    test "generates correct arguments with descriptions" do
      arguments = FieldPrompt.arguments()

      assert length(arguments) == 3

      assert %{
               "name" => "code",
               "description" => "The code to review",
               "required" => true
             } in arguments

      assert %{
               "name" => "language",
               "description" => "Programming language",
               "required" => true
             } in arguments

      assert %{
               "name" => "focus_areas",
               "description" => "Areas to focus on (optional)",
               "required" => false
             } in arguments
    end

    test "supports nested fields in prompts" do
      arguments = NestedPrompt.arguments()

      assert [
               %{
                 "name" => "config",
                 "description" => "Configuration options",
                 "required" => false
               }
             ] = arguments
    end

    test "backward compatibility with legacy prompt schemas" do
      arguments = LegacyPrompt.arguments()

      assert length(arguments) == 2

      assert %{
               "name" => "query",
               "description" => "Required string parameter",
               "required" => true
             } in arguments

      assert %{
               "name" => "max_results",
               "description" => "Optional integer parameter (default: 10)",
               "required" => false
             } in arguments
    end
  end
end
