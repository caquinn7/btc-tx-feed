defmodule BtcTxFeed.TxStatsTest do
  use ExUnit.Case, async: false

  alias BtcTxFeed.TxStats

  setup do
    start_supervised!(TxStats)
    :ok
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

  describe "record/1" do
    test "increments total_decoded" do
      TxStats.record(base_details())
      assert TxStats.get()[:total_decoded] == 1
    end

    test "increments segwit_count for segwit tx" do
      TxStats.record(base_details(%{is_segwit: true}))
      stats = TxStats.get()
      assert stats[:segwit_count] == 1
      assert stats[:legacy_count] == nil
    end

    test "increments legacy_count for non-segwit tx" do
      TxStats.record(base_details(%{is_segwit: false}))
      stats = TxStats.get()
      assert stats[:legacy_count] == 1
      assert stats[:segwit_count] == nil
    end

    test "increments coinbase_count when has_coinbase_marker is true" do
      TxStats.record(base_details(%{has_coinbase_marker: true}))
      assert TxStats.get()[:coinbase_count] == 1
    end

    test "does not increment coinbase_count for normal tx" do
      TxStats.record(base_details())
      assert TxStats.get()[:coinbase_count] == nil
    end

    test "increments validation_failure_count when validated is false" do
      TxStats.record(base_details(%{validated: false, vsize: nil}))
      assert TxStats.get()[:validation_failure_count] == 1
    end

    test "does not increment validation_failure_count when validated is true" do
      TxStats.record(base_details())
      assert TxStats.get()[:validation_failure_count] == nil
    end

    test "increments version counter" do
      TxStats.record(base_details(%{version: 2}))
      assert TxStats.get()[{:version, 2}] == 1
    end

    test "increments script_type counter for each output" do
      details =
        base_details(%{
          output_count: 2,
          outputs: [%{script_type: :p2_t_r}, %{script_type: :p2_t_r}]
        })

      TxStats.record(details)
      assert TxStats.get()[{:script_type, :p2_t_r}] == 2
    end

    test "tracks multiple distinct script types" do
      details =
        base_details(%{
          output_count: 2,
          outputs: [%{script_type: :p2_t_r}, %{script_type: :p2_w_p_k_h}]
        })

      TxStats.record(details)
      stats = TxStats.get()
      assert stats[{:script_type, :p2_t_r}] == 1
      assert stats[{:script_type, :p2_w_p_k_h}] == 1
    end

    test "does not increment vsize_bucket when validated is false" do
      TxStats.record(base_details(%{validated: false, vsize: nil}))
      stats = TxStats.get()
      assert Enum.all?(stats, fn {key, _} -> not match?({:vsize_bucket, _}, key) end)
    end

    for {label, vsize, expected_bucket} <- [
          {:tiny, 100, :tiny},
          {:small, 300, :small},
          {:medium, 750, :medium},
          {:large, 2000, :large},
          {:oversized, 6000, :oversized}
        ] do
      test "vsize_bucket is #{label} for vsize #{vsize}" do
        TxStats.record(base_details(%{vsize: unquote(vsize)}))
        assert TxStats.get()[{:vsize_bucket, unquote(expected_bucket)}] == 1
      end
    end

    for {label, count, expected_bucket} <- [
          {:single, 1, :single},
          {:few, 3, :few},
          {:many, 10, :many}
        ] do
      test "input_bucket is #{label} for count #{count}" do
        TxStats.record(base_details(%{input_count: unquote(count)}))
        assert TxStats.get()[{:input_bucket, unquote(expected_bucket)}] == 1
      end

      test "output_bucket is #{label} for count #{count}" do
        TxStats.record(base_details(%{output_count: unquote(count)}))
        assert TxStats.get()[{:output_bucket, unquote(expected_bucket)}] == 1
      end
    end

    test "accumulates counters across multiple calls" do
      TxStats.record(base_details())
      TxStats.record(base_details())
      TxStats.record(base_details())
      assert TxStats.get()[:total_decoded] == 3
    end
  end

  describe "record_failure/0" do
    test "increments total_failed" do
      TxStats.record_failure()
      assert TxStats.get()[:total_failed] == 1
    end

    test "does not affect total_decoded" do
      TxStats.record_failure()
      assert TxStats.get()[:total_decoded] == nil
    end
  end

  describe "get/0" do
    test "returns empty map when no data recorded" do
      assert TxStats.get() == %{}
    end

    test "returns a plain map" do
      TxStats.record(base_details())
      assert is_map(TxStats.get())
    end
  end
end
