defmodule BtcTxFeed.Repo.Migrations.CreateDecodeFailures do
  use Ecto.Migration

  def change do
    create table(:decode_failures) do
      add :txid, :string
      add :raw_hex, :string, null: false
      add :error_reason, :string, null: false

      timestamps(updated_at: false)
    end

    create index(:decode_failures, [:inserted_at])
  end
end
