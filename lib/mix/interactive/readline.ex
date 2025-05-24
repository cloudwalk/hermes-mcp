defmodule Mix.Interactive.Readline do
  @moduledoc """
  Basic line editing and history support for interactive shells.

  This module provides a minimal implementation of command history
  and line editing for the interactive MCP shells.
  """

  @history_size 50

  defstruct history: [],
            history_index: 0

  @doc """
  Creates a new readline state with empty history.
  """
  def new do
    %__MODULE__{history: [], history_index: 0}
  end

  @doc """
  Reads a line of input with history support.
  """
  def gets(prompt, state) do
    IO.write(prompt)

    case :io.get_line("") do
      :eof ->
        {:eof, state}

      {:error, reason} ->
        {:error, reason, state}

      data when is_list(data) or is_binary(data) ->
        line = data |> IO.chardata_to_string() |> String.trim()
        updated_state = add_history(state, line)
        {:ok, line, updated_state}
    end
  end

  @doc """
  Adds a non-empty line to history.
  """
  def add_history(state, ""), do: state

  def add_history(state, line) do
    history =
      state.history
      |> remove_duplicates(line)
      |> append_item(line)
      |> limit_size()

    %{state | history: history, history_index: 0}
  end

  defp remove_duplicates(history, line) do
    Enum.reject(history, fn item -> item == line end)
  end

  defp append_item(history, item) do
    history ++ [item]
  end

  defp limit_size(history) do
    Enum.take(history, @history_size)
  end

  @doc """
  Retrieves the command history.
  """
  def history(state) do
    state.history
  end
end
