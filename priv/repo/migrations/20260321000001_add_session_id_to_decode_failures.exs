defmodule BtcTxFeed.Repo.Migrations.AddSessionIdToDecodeFailures do
  use Ecto.Migration

  def up do
    execute "DELETE FROM decode_failures"

    alter table(:decode_failures) do
      add :stats_session_id, references(:stats_sessions, on_delete: :nilify_all)
    end
  end

  def down do
    alter table(:decode_failures) do
      remove :stats_session_id
    end
  end
end
