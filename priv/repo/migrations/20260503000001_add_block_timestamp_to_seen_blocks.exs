defmodule BtcTxFeed.Repo.Migrations.AddBlockTimestampToSeenBlocks do
  use Ecto.Migration

  def up do
    drop table(:seen_blocks)

    create table(:seen_blocks, primary_key: false) do
      add :block_hash, :string, primary_key: true
      add :block_timestamp, :naive_datetime

      timestamps(updated_at: false)
    end
  end

  def down do
    drop table(:seen_blocks)

    create table(:seen_blocks, primary_key: false) do
      add :block_hash, :string, primary_key: true

      timestamps(updated_at: false)
    end
  end
end
