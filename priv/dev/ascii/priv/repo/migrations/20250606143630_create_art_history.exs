defmodule Ascii.Repo.Migrations.CreateArtHistory do
  use Ecto.Migration

  def change do
    create table(:art_history) do
      add :text, :string, null: false
      add :font, :string, null: false
      add :result, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:art_history, [:inserted_at])
    create index(:art_history, [:text])
  end
end
