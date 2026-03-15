ExUnit.start()

Ecto.Migrator.run(BtcTxFeed.Repo, :up, all: true)
Ecto.Adapters.SQL.Sandbox.mode(BtcTxFeed.Repo, :manual)

ExUnit.after_suite(fn _ ->
  db_path =
    Application.fetch_env!(:btc_tx_feed, BtcTxFeed.Repo)
    |> Keyword.fetch!(:database)

  Enum.each([db_path, db_path <> "-shm", db_path <> "-wal"], &File.rm/1)
end)
