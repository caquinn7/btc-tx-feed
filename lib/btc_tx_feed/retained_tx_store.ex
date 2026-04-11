defmodule BtcTxFeed.RetainedTxStore do
  import Ecto.Query

  alias BtcTxFeed.{Repo, RetainedTransaction}

  @doc """
  Inserts a retained transaction row for the given corpus entry if the
  per-code limit has not yet been reached. Returns `:ok` in both cases.
  """
  def insert(txid, raw_bytes, entry) do
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
