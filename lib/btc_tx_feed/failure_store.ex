defmodule BtcTxFeed.FailureStore do
  import Ecto.Query

  alias BtcTxFeed.{Failure, Repo}

  def insert_decode_failure(txid, raw_bytes, reason, session_id) do
    do_insert(txid, raw_bytes, reason, session_id, "decode")
  end

  def insert_consensus_failure(txid, raw_bytes, errors, session_id) do
    do_insert(txid, raw_bytes, errors, session_id, "consensus")
  end

  defp do_insert(txid, raw_bytes, reason, session_id, failure_type) do
    Repo.insert!(%Failure{
      txid: txid,
      raw_hex: Base.encode16(raw_bytes, case: :lower),
      error_reason: inspect(reason),
      stats_session_id: session_id,
      failure_type: failure_type
    })

    :ok
  end

  def list_decode_failures_for_session(session_id),
    do: list_by_type("decode", session_id: session_id)

  def list_decode_failures_recent(limit \\ 50),
    do: list_by_type("decode", limit: limit)

  def list_consensus_violations_for_session(session_id),
    do: list_by_type("consensus", session_id: session_id)

  def list_consensus_violations_recent(limit \\ 50),
    do: list_by_type("consensus", limit: limit)

  defp list_by_type(type, session_id: session_id) do
    Repo.all(
      from(f in Failure,
        where: f.failure_type == ^type and f.stats_session_id == ^session_id,
        order_by: [desc: f.inserted_at]
      )
    )
  end

  defp list_by_type(type, limit: limit) do
    Repo.all(
      from(f in Failure,
        where: f.failure_type == ^type,
        order_by: [desc: f.inserted_at],
        limit: ^limit
      )
    )
  end
end
