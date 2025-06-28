defmodule Echo do
  @moduledoc """
  Echo keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Returns the version of the Specialist library.
  """
  @spec version() :: String.t() | nil
  def version do
    if vsn = Application.spec(:echo)[:vsn] do
      List.to_string(vsn)
    end
  end
end
