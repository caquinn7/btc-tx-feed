defmodule BtcTxFeed.TxSampler do
  @moduledoc """
  GenServer that maintains a bounded queue of txids received from the mempool
  PubSub feed and processes one per second, fetching raw bytes and driving the
  decode/stats pipeline.
  """

  use GenServer

  require Logger

  alias BtcTxFeed.{FailureStore, MempoolHttpClient, TxParser, TxStats}

  @queue_cap 500
  @tick_ms 1_000

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
    Phoenix.PubSub.subscribe(BtcTxFeed.PubSub, "mempool:txids")
    Process.send_after(self(), :tick, @tick_ms)
    {:ok, %{queue: :queue.new(), queue_size: 0}}
  end

  @impl true
  def handle_info({:new_txids, txids}, state) do
    state = Enum.reduce(txids, state, &enqueue/2)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)

    case :queue.out(state.queue) do
      {:empty, _} ->
        {:noreply, state}

      {{:value, txid}, rest} ->
        state = %{state | queue: rest, queue_size: state.queue_size - 1}
        Task.start(fn -> process(txid) end)
        {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp enqueue(txid, %{queue_size: size} = state) when size < @queue_cap do
    %{state | queue: :queue.in(txid, state.queue), queue_size: size + 1}
  end

  defp enqueue(txid, state) do
    # Queue is full — drop the oldest entry and push the new one at the back
    {_, rest} = :queue.out(state.queue)
    %{state | queue: :queue.in(txid, rest)}
  end

  defp process(txid) do
    case MempoolHttpClient.get_raw_tx(txid) do
      {:ok, raw} ->
        try do
          case TxParser.parse(raw) do
            {:ok, details} ->
              TxStats.record(details)

            {:error, reason} ->
              TxStats.record_failure()
              FailureStore.insert(nil, raw, reason)
          end
        rescue
          e ->
            TxStats.record_failure()
            FailureStore.insert(nil, raw, Exception.message(e))
        end

      {:error, _} ->
        # HTTP error / 429 — drop silently
        :ok
    end
  end
end
