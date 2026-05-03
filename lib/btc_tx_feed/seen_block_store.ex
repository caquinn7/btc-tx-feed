defmodule BtcTxFeed.SeenBlockStore do
  import Ecto.Query

  alias BtcTxFeed.Repo

  @doc """
  Returns a MapSet of all known block hashes. Called once at GenServer init
  for fast in-memory lookups.
  """
  def all_hashes do
    Repo.all(from(s in "seen_blocks", select: s.block_hash))
    |> MapSet.new()
  end

  @doc """
  Inserts a block hash. No-ops silently on conflict (idempotent).
  """
  def insert!(block_hash) do
    Repo.insert_all(
      "seen_blocks",
      [%{block_hash: block_hash, inserted_at: DateTime.utc_now(:second)}],
      on_conflict: :nothing,
      conflict_target: [:block_hash]
    )

    :ok
  end
end
