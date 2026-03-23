defmodule BtcTxFeed.Repo.Migrations.AddDecodePolicyToStatsSessions do
  use Ecto.Migration

  def change do
    alter table(:stats_sessions) do
      add :decode_policy, :binary
    end
  end
end
