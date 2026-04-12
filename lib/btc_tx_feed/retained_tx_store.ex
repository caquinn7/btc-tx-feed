defmodule BtcTxFeed.RetainedTxStore do
  import Ecto.Query

  alias BtcTxFeed.{Repo, RetainedTransaction}

  @doc """
  Inserts a retained transaction row for the given corpus entry if the
  per-code limit has not yet been reached. Returns `:ok` in both cases.

  The cap check is a non-atomic count-then-insert. This is safe under the
  current `TxSampler` design (one tx processed per second), where concurrent
  inserts for the same corpus_code are unlikely. If throughput increases,
  serialise inserts via a GenServer or a DB-level locking strategy to prevent
  the limit from being exceeded by racing tasks.
  """
  def insert!(txid, raw_bytes, entry) do
    count =
      Repo.aggregate(
        from(r in RetainedTransaction, where: r.corpus_code == ^entry.code),
        :count
      )

    if count < entry.limit do
      %{
        txid: txid,
        corpus_code: entry.code,
        corpus_label: entry.label,
        raw_hex: Base.encode16(raw_bytes, case: :lower),
        matched_rule: inspect(entry.rule)
      }
      |> RetainedTransaction.changeset()
      |> Repo.insert!()
    end

    :ok
  end
end
