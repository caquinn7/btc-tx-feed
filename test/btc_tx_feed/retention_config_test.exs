defmodule BtcTxFeed.RetentionConfigTest do
  use ExUnit.Case, async: false

  alias BtcTxFeed.RetentionConfig

  @details %{
    version: 1,
    is_segwit: true,
    input_count: 1,
    output_count: 2,
    output_script_type_counts: %{p2_w_p_k_h: 1, null_data: 1},
    witness_item_counts_per_input: [2],
    witness_total_items: 2,
    witness_total_bytes: 100,
    largest_witness_item_bytes: 72
  }

  setup do
    original = Application.get_env(:btc_tx_feed, :retention_rules)

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:btc_tx_feed, :retention_rules)
      else
        Application.put_env(:btc_tx_feed, :retention_rules, original)
      end
    end)

    :ok
  end

  describe "entries/0" do
    test "returns empty list when no entries are configured" do
      Application.put_env(:btc_tx_feed, :retention_rules, [])
      assert RetentionConfig.entries() == []
    end

    test "returns the configured entries" do
      entries = [
        %{code: "F01", label: "OP_RETURN", limit: 10, rule: {:has_output_script_type, :null_data}}
      ]

      Application.put_env(:btc_tx_feed, :retention_rules, entries)
      assert RetentionConfig.entries() == entries
    end
  end

  describe "matching_entries/1" do
    test "returns empty list when no entries are configured" do
      Application.put_env(:btc_tx_feed, :retention_rules, [])
      assert RetentionConfig.matching_entries(@details) == []
    end

    test "returns matching entries" do
      entries = [
        %{code: "F01", label: "Non-segwit", limit: 10, rule: {:eq, :is_segwit, false}},
        %{code: "F02", label: "Segwit", limit: 10, rule: {:eq, :is_segwit, true}}
      ]

      Application.put_env(:btc_tx_feed, :retention_rules, entries)

      assert RetentionConfig.matching_entries(@details) == [Enum.at(entries, 1)]
    end

    test "returns empty list when no entries match" do
      entries = [
        %{code: "F01", label: "Non-segwit", limit: 10, rule: {:eq, :is_segwit, false}},
        %{code: "F02", label: "Many inputs", limit: 10, rule: {:gte, :input_count, 10}}
      ]

      Application.put_env(:btc_tx_feed, :retention_rules, entries)

      assert RetentionConfig.matching_entries(@details) == []
    end

    test "returns multiple entries when a tx satisfies more than one rule" do
      entries = [
        %{
          code: "F01",
          label: "OP_RETURN",
          limit: 10,
          rule: {:has_output_script_type, :null_data}
        },
        %{code: "F02", label: "Segwit", limit: 10, rule: {:eq, :is_segwit, true}}
      ]

      Application.put_env(:btc_tx_feed, :retention_rules, entries)

      assert RetentionConfig.matching_entries(@details) == entries
    end

    test "returns matching entry for a composite rule" do
      entry = %{
        code: "C01",
        label: "Segwit with OP_RETURN",
        limit: 5,
        rule: {:all, [{:eq, :is_segwit, true}, {:has_output_script_type, :null_data}]}
      }

      Application.put_env(:btc_tx_feed, :retention_rules, [entry])

      assert RetentionConfig.matching_entries(@details) == [entry]
    end
  end
end
