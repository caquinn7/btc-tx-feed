defmodule BtcTxFeed.Repo.Migrations.CreateSeenBlocks do
  use Ecto.Migration

  def change do
    create table(:seen_blocks, primary_key: false) do
      add :block_hash, :string, primary_key: true

      timestamps(updated_at: false)
    end
  end
end
