defmodule BtcTxFeed.CoinbaseSampler do
  @moduledoc """
  GenServer that periodically polls mempool.space for recent blocks, fetches
  the coinbase transaction (index 0) for each unseen block, parses it, and
  runs it through the retention pipeline.

  Coinbase transactions are deliberately excluded from TxStats to avoid
  skewing mempool statistics.
  """

  use GenServer

  require Logger

  alias BtcTxFeed.{
    FailureStore,
    MempoolHttpClient,
    RetentionConfig,
    RetainedTxStore,
    SeenBlockStore,
    TxParser,
    TxStats
  }

  @tick_ms 60_000
  @backoff_ms 30_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    seen_block_ids = SeenBlockStore.all_hashes()
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, %{seen_block_ids: seen_block_ids, resume_at: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)

    if state.resume_at && System.monotonic_time(:millisecond) < state.resume_at do
      {:noreply, state}
    else
      state = process_new_blocks(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:backoff, state) do
    resume_at = System.monotonic_time(:millisecond) + @backoff_ms
    Logger.warning("CoinbaseSampler: 429 received, backing off for #{@backoff_ms}ms")
    {:noreply, %{state | resume_at: resume_at}}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp process_new_blocks(state) do
    case MempoolHttpClient.get_recent_blocks() do
      {:ok, blocks} ->
        new_block_ids =
          blocks
          |> Enum.map(& &1["id"])
          |> Enum.reject(&MapSet.member?(state.seen_block_ids, &1))

        process_blocks(new_block_ids, state)

      {:error, {:http_error, 429}} ->
        send(self(), :backoff)
        state

      {:error, reason} ->
        Logger.error("CoinbaseSampler: failed to fetch recent blocks: #{inspect(reason)}")
        state
    end
  end

  defp process_blocks([], state), do: state

  defp process_blocks([block_id | rest], state) do
    case fetch_and_process_coinbase(block_id, state) do
      {:ok, state} -> process_blocks(rest, state)
      {:backoff, state} -> state
    end
  end

  defp fetch_and_process_coinbase(block_id, state) do
    case MempoolHttpClient.get_block_txid(block_id, 0) do
      {:ok, txid} ->
        case MempoolHttpClient.get_raw_tx(txid) do
          {:ok, raw} ->
            process_raw(txid, raw)
            state = mark_seen(state, block_id)
            {:ok, state}

          {:error, {:http_error, 429}} ->
            send(self(), :backoff)
            {:backoff, state}

          {:error, reason} ->
            Logger.error(
              "CoinbaseSampler: failed to fetch raw tx for block #{block_id}: #{inspect(reason)}"
            )

            state = mark_seen(state, block_id)
            {:ok, state}
        end

      {:error, {:http_error, 429}} ->
        send(self(), :backoff)
        {:backoff, state}

      {:error, reason} ->
        Logger.error(
          "CoinbaseSampler: failed to fetch txid for block #{block_id}: #{inspect(reason)}"
        )

        {:ok, state}
    end
  end

  defp process_raw(txid, raw) do
    parse_result =
      try do
        TxParser.parse(raw)
      rescue
        e -> {:error, Exception.message(e)}
      end

    case parse_result do
      {:ok, details} ->
        try do
          details
          |> RetentionConfig.matching_entries()
          |> Enum.each(fn entry -> RetainedTxStore.insert!(txid, raw, entry) end)
        rescue
          e ->
            Logger.error(
              "CoinbaseSampler: retention insert failed for #{txid}: #{Exception.message(e)}"
            )
        end

        Logger.debug("CoinbaseSampler: fetched coinbase #{txid}")

      {:error, reason} ->
        FailureStore.insert_decode_failure!(txid, raw, reason, TxStats.get_session_id())
    end
  end

  defp mark_seen(state, block_id) do
    SeenBlockStore.insert!(block_id)
    %{state | seen_block_ids: MapSet.put(state.seen_block_ids, block_id)}
  end
end
