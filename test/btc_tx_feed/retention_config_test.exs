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

  describe "rules/0" do
    test "returns empty list when no rules are configured" do
      Application.put_env(:btc_tx_feed, :retention_rules, [])
      assert RetentionConfig.rules() == []
    end

    test "returns the configured rules" do
      rules = [{:eq, :is_segwit, true}]
      Application.put_env(:btc_tx_feed, :retention_rules, rules)
      assert RetentionConfig.rules() == rules
    end
  end

  describe "any_match?/1" do
    test "returns false when no rules are configured" do
      Application.put_env(:btc_tx_feed, :retention_rules, [])
      refute RetentionConfig.any_match?(@details)
    end

    test "returns true when at least one rule matches" do
      Application.put_env(:btc_tx_feed, :retention_rules, [
        {:eq, :is_segwit, false},
        {:eq, :is_segwit, true}
      ])

      assert RetentionConfig.any_match?(@details)
    end

    test "returns false when no rules match" do
      Application.put_env(:btc_tx_feed, :retention_rules, [
        {:eq, :is_segwit, false},
        {:gte, :input_count, 10}
      ])

      refute RetentionConfig.any_match?(@details)
    end

    test "returns true when a composite rule matches" do
      Application.put_env(:btc_tx_feed, :retention_rules, [
        {:all,
         [
           {:eq, :is_segwit, true},
           {:has_output_script_type, :null_data}
         ]}
      ])

      assert RetentionConfig.any_match?(@details)
    end
  end
end
