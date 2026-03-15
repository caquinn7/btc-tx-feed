ExUnit.start()

Ecto.Migrator.run(BtcTxFeed.Repo, :up, all: true)
Ecto.Adapters.SQL.Sandbox.mode(BtcTxFeed.Repo, :manual)
