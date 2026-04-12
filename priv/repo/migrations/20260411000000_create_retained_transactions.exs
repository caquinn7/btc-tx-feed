defmodule BtcTxFeed.Repo.Migrations.CreateRetainedTransactions do
  use Ecto.Migration

  def change do
    create table(:retained_transactions) do
      add :txid, :string, null: false
      add :corpus_code, :string, null: false
      add :corpus_label, :string, null: false
      add :raw_hex, :string, null: false
      add :matched_rule, :string, null: false

      timestamps(updated_at: false)
    end

    create index(:retained_transactions, [:corpus_code])
    create index(:retained_transactions, [:inserted_at])
  end
end
