defmodule BtcTxFeed.FailureStore do
  import Ecto.Query

  alias BtcTxFeed.{Failure, Repo}

  def insert(txid, raw_bytes, reason, session_id) do
    raw_hex = Base.encode16(raw_bytes, case: :lower)

    Repo.insert!(%Failure{
      txid: txid,
      raw_hex: raw_hex,
      error_reason: inspect(reason),
      stats_session_id: session_id
    })

    :ok
  end

  def list_for_session(session_id) do
    Repo.all(
      from(f in Failure,
        where: f.stats_session_id == ^session_id,
        order_by: [desc: f.inserted_at]
      )
    )
  end

  def list_recent(limit \\ 50) do
    Repo.all(
      from(f in Failure,
        order_by: [desc: f.inserted_at],
        limit: ^limit
      )
    )
  end
end
