defmodule BtcTxFeed.StatsSessions do
  import Ecto.Query

  alias BtcTxFeed.{Repo, StatsSession}

  @doc """
  Opens a new session row with the given `started_at` timestamp and
  `decode_policy_map` snapshot. Returns the inserted struct including its
  database-assigned `id`.
  """
  def create_open!(%DateTime{} = started_at, decode_policy_map) do
    Repo.insert!(%StatsSession{
      started_at: DateTime.truncate(started_at, :second),
      decode_policy: :erlang.term_to_binary(decode_policy_map)
    })
  end

  @doc """
  Writes the current `counters_map` to the session row without finalizing it.
  Also updates the `total_decoded` and `total_failed` denormalized columns.
  Intended to be called periodically so that counter data survives an unclean
  shutdown. Only updates open sessions (those with `ended_at IS NULL`), so a
  stale flush after finalization is a safe no-op.
  """
  def checkpoint!(id, counters_map) do
    total_decoded = Map.get(counters_map, :total_decoded, 0)
    total_failed = Map.get(counters_map, :total_failed, 0)

    Repo.update_all(
      from(s in StatsSession, where: s.id == ^id and is_nil(s.ended_at)),
      set: [
        counters: :erlang.term_to_binary(counters_map),
        total_decoded: total_decoded,
        total_failed: total_failed
      ]
    )

    :ok
  end

  @doc """
  Closes a session by setting `ended_at`, persisting the final `counters_map`,
  and recording the `end_reason`. Valid reasons are `:shutdown` (clean OTP
  termination) and `:startup_recovery` (orphan recovered at next boot).
  Raises if the row is not found or the update affects more than one row.
  """
  def finalize!(id, counters_map, %DateTime{} = ended_at, end_reason)
      when end_reason in [:shutdown, :startup_recovery] do
    total_decoded = Map.get(counters_map, :total_decoded, 0)
    total_failed = Map.get(counters_map, :total_failed, 0)

    {1, _} =
      Repo.update_all(
        from(s in StatsSession, where: s.id == ^id),
        set: [
          ended_at: DateTime.truncate(ended_at, :second),
          counters: :erlang.term_to_binary(counters_map),
          total_decoded: total_decoded,
          total_failed: total_failed,
          end_reason: Atom.to_string(end_reason)
        ]
      )

    :ok
  end

  @doc """
  Finalizes any open sessions (ended_at IS NULL) left over from a previous
  run that did not shut down cleanly. Uses the last checkpointed counters.
  Called once during TxStats startup.
  """
  def recover_orphans! do
    orphans =
      Repo.all(
        from(s in StatsSession,
          where: is_nil(s.ended_at),
          select: %{id: s.id, counters: s.counters}
        )
      )

    now = DateTime.utc_now()

    Enum.each(orphans, fn %{id: id, counters: raw_counters} ->
      counters =
        if raw_counters, do: :erlang.binary_to_term(raw_counters), else: %{}

      finalize!(id, counters, now, :startup_recovery)
    end)

    length(orphans)
  end

  @doc """
  Returns all finalized sessions (those with a non-nil `ended_at`), ordered
  by `started_at` descending. The returned maps include `id`, `started_at`,
  `ended_at`, `total_decoded`, `total_failed`, and `end_reason`, but not the
  raw `counters` blob.
  """
  def list do
    Repo.all(
      from(s in StatsSession,
        where: not is_nil(s.ended_at),
        select: %{
          id: s.id,
          started_at: s.started_at,
          ended_at: s.ended_at,
          total_decoded: s.total_decoded,
          total_failed: s.total_failed,
          end_reason: s.end_reason
        },
        order_by: [desc: s.started_at]
      )
    )
  end

  @doc """
  Fetches a single session by `id` and deserializes the `counters` and
  `decode_policy` binary fields into Elixir terms. Works for both open and
  finalized sessions. Raises `Ecto.NoResultsError` if not found.
  """
  def get!(id) do
    session = Repo.get!(StatsSession, id)
    counters = if session.counters, do: :erlang.binary_to_term(session.counters), else: nil

    decode_policy =
      if session.decode_policy, do: :erlang.binary_to_term(session.decode_policy), else: nil

    %{session | counters: counters, decode_policy: decode_policy}
  end
end
