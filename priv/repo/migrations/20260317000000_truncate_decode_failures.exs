defmodule BtcTxFeed.Repo.Migrations.TruncateDecodeFailures do
  use Ecto.Migration

  def up do
    execute("DELETE FROM decode_failures")
  end

  def down, do: :ok
end
