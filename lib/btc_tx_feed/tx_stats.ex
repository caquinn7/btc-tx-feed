defmodule BtcTxFeed.TxStats do
  @moduledoc """
  GenServer that owns an ETS table of aggregate transaction stats.
  All public functions operate on ETS directly — the GenServer only
  initialises the table and owns its lifetime.
  """

  use GenServer

  @table :tx_stats

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
    :ets.tab2list(@table)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, nil}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp increment(key) do
    :ets.update_counter(@table, key, 1, {key, 0})
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
