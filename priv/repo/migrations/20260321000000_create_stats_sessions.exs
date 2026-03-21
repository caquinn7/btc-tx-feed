defmodule BtcTxFeed.Repo.Migrations.CreateStatsSessions do
  use Ecto.Migration

  def change do
    create table(:stats_sessions) do
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :counters, :binary
      add :total_decoded, :integer, null: false, default: 0
      add :total_failed, :integer, null: false, default: 0
    end
  end
end
