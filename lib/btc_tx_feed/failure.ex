defmodule BtcTxFeed.Failure do
  use Ecto.Schema

  schema "decode_failures" do
    field(:txid, :string)
    field(:raw_hex, :string)
    field(:error_reason, :string)
    field(:stats_session_id, :integer)
    field(:failure_type, :string)

    timestamps(updated_at: false)
  end
end
