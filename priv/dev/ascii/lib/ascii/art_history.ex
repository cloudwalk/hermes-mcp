defmodule Ascii.ArtHistory do
  @moduledoc """
  Schema and context for storing ASCII art generation history.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Ascii.Repo

  schema "art_history" do
    field :text, :string
    field :font, :string
    field :result, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(art_history, attrs) do
    art_history
    |> cast(attrs, [:text, :font, :result])
    |> validate_required([:text, :font, :result])
    |> validate_length(:text, max: 100)
    |> validate_inclusion(:font, ["standard", "slant", "3d", "banner"])
  end

  @doc """
  Creates a new art history entry.
  """
  def create_art(attrs \\ %{}) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists recent art history entries.
  """
  def list_recent(limit \\ 10) do
    __MODULE__
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets art history by ID.
  """
  def get_art!(id) do
    Repo.get!(__MODULE__, id)
  end

  @doc """
  Searches art history by text.
  """
  def search_by_text(search_term) do
    like_term = "%#{search_term}%"

    __MODULE__
    |> where([a], ilike(a.text, ^like_term))
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Deletes art history by ID.
  """
  def delete_art(id) do
    __MODULE__
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      art -> Repo.delete(art)
    end
  end

  @doc """
  Gets statistics about art generation.
  """
  def get_stats do
    font_stats =
      __MODULE__
      |> group_by([a], a.font)
      |> select([a], {a.font, count(a.id)})
      |> Repo.all()
      |> Map.new()

    total_count =
      __MODULE__
      |> Repo.aggregate(:count, :id)

    %{
      total_generations: total_count,
      font_usage: font_stats
    }
  end
end
