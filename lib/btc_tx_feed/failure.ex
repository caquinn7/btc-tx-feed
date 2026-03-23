defmodule BtcTxFeed.Failure do
  use Ecto.Schema

  schema "decode_failures" do
    field(:txid, :string)
    field(:raw_hex, :string)
    field(:error_reason, :string)

    timestamps(updated_at: false)
  end
end
