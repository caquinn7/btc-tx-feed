defmodule BtcTxFeed.TxStats do
  @moduledoc """
  GenServer that owns an ETS table of aggregate transaction stats.
  All public functions operate on ETS directly — the GenServer only
  initialises the table and owns its lifetime.
  """

  use GenServer

  @table :tx_stats
  @flush_interval if Mix.env() == :prod, do: :timer.minutes(5), else: :timer.seconds(30)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Increments all relevant counters from a successfully parsed transaction.
  Accepts the details map produced by `BtcTxFeed.TxParser.parse/1`.
  """
  def record(details) do
    increment(:total_decoded)

    if details.is_segwit,
      do: increment(:segwit_count),
      else: increment(:legacy_count)

    if details.has_coinbase_marker, do: increment(:coinbase_count)

    if not details.validated, do: increment(:validation_failure_count)

    increment({:version, details.version})

    Enum.each(details.outputs, fn output ->
      increment({:script_type, output.script_type})
    end)

    if vsize = Map.get(details, :vsize) do
      increment({:vsize_bucket, vsize_bucket(vsize)})
    end

    increment({:input_bucket, count_bucket(details.input_count)})
    increment({:output_bucket, count_bucket(details.output_count)})
  end

  @doc "Increments the total failure counter."
  def record_failure do
    increment(:total_failed)
  end

  @doc "Returns a plain map of all counters for the dashboard."
  def get do
    case :ets.whereis(@table) do
      :undefined ->
        %{}

      _ ->
        Map.new(:ets.tab2list(@table))
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)

    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    load_snapshot()
    schedule_flush()

    {:ok, nil}
  end

  @impl true
  def handle_info(:flush, state) do
    persist_snapshot()
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    require Logger
    Logger.info("TxStats: terminate/2 called (#{inspect(reason)}), flushing snapshot")
    persist_snapshot()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp increment(key) do
    :ets.update_counter(@table, key, 1, {key, 0})
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end

  defp snapshot_path do
    Application.get_env(:btc_tx_feed, :tx_stats_snapshot_path)
  end

  defp load_snapshot do
    case snapshot_path() do
      nil ->
        :ok

      path ->
        case File.read(path) do
          {:ok, binary} ->
            entries = :erlang.binary_to_term(binary)
            :ets.insert(@table, entries)

          {:error, :enoent} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.warning("TxStats: could not read snapshot #{path}: #{inspect(reason)}")
        end
    end
  end

  defp persist_snapshot do
    case snapshot_path() do
      nil ->
        :ok

      path ->
        entries = :ets.tab2list(@table)
        binary = :erlang.term_to_binary(entries)
        tmp = path <> ".tmp"

        with :ok <- File.write(tmp, binary),
             :ok <- :file.rename(tmp, path) do
          :ok
        else
          {:error, reason} ->
            require Logger
            Logger.error("TxStats: snapshot write failed: #{inspect(reason)}")
        end
    end
  end

  defp vsize_bucket(v) when v < 250, do: :tiny
  defp vsize_bucket(v) when v < 500, do: :small
  defp vsize_bucket(v) when v < 1000, do: :medium
  defp vsize_bucket(v) when v < 5000, do: :large
  defp vsize_bucket(_), do: :oversized

  defp count_bucket(1), do: :single
  defp count_bucket(n) when n <= 5, do: :few
  defp count_bucket(_), do: :many
end
