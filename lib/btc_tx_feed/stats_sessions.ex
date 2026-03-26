defmodule BtcTxFeed.StatsSessions do
  import Ecto.Query

  alias BtcTxFeed.{Repo, StatsSession}

  def create_open!(%DateTime{} = started_at, decode_policy_map) do
    Repo.insert!(%StatsSession{
      started_at: DateTime.truncate(started_at, :second),
      decode_policy: :erlang.term_to_binary(decode_policy_map)
    })
  end

  def checkpoint!(id, counters_map) do
    total_decoded = Map.get(counters_map, :total_decoded, 0)
    total_failed = Map.get(counters_map, :total_failed, 0)

    Repo.update_all(
      from(s in StatsSession, where: s.id == ^id),
      set: [
        counters: :erlang.term_to_binary(counters_map),
        total_decoded: total_decoded,
        total_failed: total_failed
      ]
    )

    :ok
  end

  def finalize!(id, counters_map, %DateTime{} = ended_at) do
    total_decoded = Map.get(counters_map, :total_decoded, 0)
    total_failed = Map.get(counters_map, :total_failed, 0)

    {1, _} =
      Repo.update_all(
        from(s in StatsSession, where: s.id == ^id),
        set: [
          ended_at: DateTime.truncate(ended_at, :second),
          counters: :erlang.term_to_binary(counters_map),
          total_decoded: total_decoded,
          total_failed: total_failed
        ]
      )

    :ok
  end

  def list do
    Repo.all(
      from(s in StatsSession,
        where: not is_nil(s.ended_at),
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
    counters = if session.counters, do: :erlang.binary_to_term(session.counters), else: nil

    decode_policy =
      if session.decode_policy, do: :erlang.binary_to_term(session.decode_policy), else: nil

    %{session | counters: counters, decode_policy: decode_policy}
  end
end
