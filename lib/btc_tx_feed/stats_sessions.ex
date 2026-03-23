defmodule BtcTxFeed.StatsSessions do
  import Ecto.Query

  alias BtcTxFeed.{Repo, StatsSession}

  def archive!(counters_map, %DateTime{} = started_at, %DateTime{} = ended_at) do
    total_decoded = Map.get(counters_map, :total_decoded, 0)
    total_failed = Map.get(counters_map, :total_failed, 0)

    Repo.insert!(%StatsSession{
      started_at: DateTime.truncate(started_at, :second),
      ended_at: DateTime.truncate(ended_at, :second),
      counters: :erlang.term_to_binary(counters_map),
      total_decoded: total_decoded,
      total_failed: total_failed
    })

    :ok
  end

  def list do
    Repo.all(
      from(s in StatsSession,
        select: %{
          id: s.id,
          started_at: s.started_at,
          ended_at: s.ended_at,
          total_decoded: s.total_decoded,
          total_failed: s.total_failed
        },
        order_by: [desc: s.started_at]
      )
    )
  end

  def get!(id) do
    session = Repo.get!(StatsSession, id)
    %{session | counters: :erlang.binary_to_term(session.counters)}
  end
end
