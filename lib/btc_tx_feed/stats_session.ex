defmodule BtcTxFeed.StatsSession do
  use Ecto.Schema

  schema "stats_sessions" do
    field(:started_at, :utc_datetime)
    field(:ended_at, :utc_datetime)
    field(:counters, :binary)
    field(:decode_policy, :binary)
    field(:total_decoded, :integer)
    field(:total_failed, :integer)
    field(:end_reason, :string)
  end
end
