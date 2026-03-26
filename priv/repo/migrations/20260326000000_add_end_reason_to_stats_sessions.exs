defmodule BtcTxFeed.Repo.Migrations.AddEndReasonToStatsSessions do
  use Ecto.Migration

  def change do
    alter table(:stats_sessions) do
      add :end_reason, :string, null: true
    end
  end
end
