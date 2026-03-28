defmodule BtcTxFeed.Repo.Migrations.AddFailureTypeToDecodeFailures do
  use Ecto.Migration

  def change do
    alter table(:decode_failures) do
      add :failure_type, :string, null: false, default: "decode"
    end

    drop index(:decode_failures, [:inserted_at])
    create index(:decode_failures, [:failure_type, :inserted_at])
    create index(:decode_failures, [:stats_session_id, :failure_type, :inserted_at])
  end
end
