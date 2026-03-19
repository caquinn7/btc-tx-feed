defmodule BtcTxFeed.TxStatsPersistenceTest do
  use ExUnit.Case, async: false

  alias BtcTxFeed.TxStats

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "tx_stats_test_#{:erlang.unique_integer([:positive])}.bin"
      )

    Application.put_env(:btc_tx_feed, :tx_stats_snapshot_path, path)

    on_exit(fn ->
      Application.put_env(:btc_tx_feed, :tx_stats_snapshot_path, nil)
      File.rm(path)
      File.rm(path <> ".tmp")
    end)

    %{path: path}
  end

  defp base_details(overrides \\ %{}) do
    Map.merge(
      %{
        version: 2,
        is_segwit: false,
        has_coinbase_marker: false,
        validated: true,
        vsize: 200,
        input_count: 1,
        output_count: 1,
        outputs: [%{script_type: :p2_w_p_k_h}]
      },
      overrides
    )
  end

  describe "terminate/2" do
    test "writes snapshot file when GenServer stops", %{path: path} do
      start_supervised!(TxStats)
      TxStats.record(base_details())
      stop_supervised!(TxStats)

      assert File.exists?(path)
    end

    test "persisted counters are restored after restart", %{path: path} do
      start_supervised!(TxStats)
      TxStats.record(base_details())
      TxStats.record(base_details())
      stop_supervised!(TxStats)

      assert File.exists?(path)

      start_supervised!(TxStats)
      assert TxStats.get()[:total_decoded] == 2
    end

    test "restores all counter types after restart", %{path: path} do
      start_supervised!(TxStats)

      TxStats.record(base_details(%{is_segwit: true, vsize: 300}))
      TxStats.record(base_details(%{is_segwit: false, vsize: 100, input_count: 3}))

      stop_supervised!(TxStats)
      assert File.exists?(path)

      start_supervised!(TxStats)
      stats = TxStats.get()

      assert stats[:total_decoded] == 2
      assert stats[:segwit_count] == 1
      assert stats[:legacy_count] == 1
      assert stats[{:vsize_bucket, :small}] == 1
      assert stats[{:vsize_bucket, :tiny}] == 1
      assert stats[{:input_bucket, :few}] == 1
    end
  end

  describe "periodic flush via :flush message" do
    test "writes snapshot file when :flush is received", %{path: path} do
      start_supervised!(TxStats)
      TxStats.record(base_details())

      send(Process.whereis(TxStats), :flush)
      _ = :sys.get_state(TxStats)

      assert File.exists?(path)
    end

    test "snapshot written by flush restores counters on restart", %{path: _path} do
      start_supervised!(TxStats)
      TxStats.record(base_details())
      TxStats.record(base_details())

      send(Process.whereis(TxStats), :flush)
      _ = :sys.get_state(TxStats)

      stop_supervised!(TxStats)
      start_supervised!(TxStats)

      assert TxStats.get()[:total_decoded] == 2
    end
  end

  describe "load_snapshot/0" do
    test "boots cleanly with empty table when no snapshot exists", %{path: _path} do
      start_supervised!(TxStats)
      assert TxStats.get() == %{}
    end

    test "boots cleanly with empty table when snapshot is corrupt", %{path: path} do
      File.write!(path, "this is not a valid erlang term binary")
      start_supervised!(TxStats)
      assert TxStats.get() == %{}
    end

    test "boots cleanly with empty table when snapshot is a valid binary but wrong shape",
         %{path: path} do
      File.write!(path, :erlang.term_to_binary(%{not: "a list of tuples"}))
      start_supervised!(TxStats)
      assert TxStats.get() == %{}
    end

    test "restores counters from a manually written snapshot", %{path: path} do
      entries = [
        {:total_decoded, 7},
        {:legacy_count, 5},
        {:segwit_count, 2},
        {{:version, 2}, 7}
      ]

      File.write!(path, :erlang.term_to_binary(entries))

      start_supervised!(TxStats)
      stats = TxStats.get()

      assert stats[:total_decoded] == 7
      assert stats[:legacy_count] == 5
      assert stats[:segwit_count] == 2
      assert stats[{:version, 2}] == 7
    end
  end
end
