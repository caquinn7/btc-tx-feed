defmodule BtcTxFeed.Repo do
  use Ecto.Repo,
    otp_app: :btc_tx_feed,
    adapter: Ecto.Adapters.SQLite3
end
