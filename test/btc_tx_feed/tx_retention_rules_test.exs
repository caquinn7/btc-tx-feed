defmodule BtcTxFeed.TxRetentionRulesTest do
  use ExUnit.Case, async: true

  alias BtcTxFeed.TxRetentionRules

  # ---------------------------------------------------------------------------
  # Minimal details_map fixtures used across tests.
  # These mirror the shape returned by BtcTxFeed.TxParser.parse/1.
  # ---------------------------------------------------------------------------

  @legacy_details %{
    version: 1,
    is_segwit: false,
    lock_time: 0,
    has_coinbase_marker: false,
    validated: true,
    input_count: 3,
    output_count: 2,
    base_size: 400,
    total_size: 400,
    weight: 1600,
    vsize: 400,
    output_script_types: [:p2_p_k_h, :p2_p_k_h],
    output_script_type_counts: %{p2_p_k_h: 2},
    has_op_return: false,
    op_return_output_count: 0,
    has_non_standard_output: false,
    witness_item_counts_per_input: [],
    witness_total_items: 0,
    witness_total_bytes: 0,
    largest_witness_item_bytes: 0,
    inputs_with_witness_count: 0
  }

  @segwit_details %{
    version: 1,
    is_segwit: true,
    lock_time: 0,
    has_coinbase_marker: false,
    validated: true,
    input_count: 2,
    output_count: 2,
    base_size: 225,
    total_size: 372,
    weight: 1047,
    vsize: 262,
    output_script_types: [:p2_w_p_k_h, :p2_w_p_k_h],
    output_script_type_counts: %{p2_w_p_k_h: 2},
    has_op_return: false,
    op_return_output_count: 0,
    has_non_standard_output: false,
    witness_item_counts_per_input: [2, 2],
    witness_total_items: 4,
    witness_total_bytes: 210,
    largest_witness_item_bytes: 72,
    inputs_with_witness_count: 2
  }

  @op_return_details %{
    version: 1,
    is_segwit: false,
    lock_time: 0,
    has_coinbase_marker: false,
    validated: true,
    input_count: 1,
    output_count: 2,
    base_size: 103,
    total_size: 103,
    weight: 412,
    vsize: 103,
    output_script_types: [:p2_p_k_h, :null_data],
    output_script_type_counts: %{p2_p_k_h: 1, null_data: 1},
    has_op_return: true,
    op_return_output_count: 1,
    has_non_standard_output: false,
    witness_item_counts_per_input: [],
    witness_total_items: 0,
    witness_total_bytes: 0,
    largest_witness_item_bytes: 0,
    inputs_with_witness_count: 0
  }

  # ---------------------------------------------------------------------------
  # validate_rule/1 — structural validation
  # ---------------------------------------------------------------------------

  describe "validate_rule/1 — boolean composition" do
    test "accepts {:all, [rule, ...]}" do
      assert :ok = TxRetentionRules.validate_rule({:all, [{:eq, :is_segwit, false}]})
    end

    test "accepts {:any, [rule, ...]}" do
      assert :ok = TxRetentionRules.validate_rule({:any, [{:eq, :is_segwit, true}]})
    end

    test "accepts {:not, rule}" do
      assert :ok = TxRetentionRules.validate_rule({:not, {:eq, :is_segwit, true}})
    end

    test "accepts nested composition" do
      rule =
        {:all,
         [
           {:eq, :is_segwit, false},
           {:any, [{:gte, :input_count, 3}, {:lte, :output_count, 1}]}
         ]}

      assert :ok = TxRetentionRules.validate_rule(rule)
    end

    test "rejects empty :all list" do
      assert {:error, _} = TxRetentionRules.validate_rule({:all, []})
    end

    test "rejects empty :any list" do
      assert {:error, _} = TxRetentionRules.validate_rule({:any, []})
    end

    test "rejects :all with a non-list second element" do
      assert {:error, _} = TxRetentionRules.validate_rule({:all, :bad})
    end
  end

  describe "validate_rule/1 — scalar comparisons" do
    test "accepts {:eq, field, value}" do
      assert :ok = TxRetentionRules.validate_rule({:eq, :is_segwit, false})
    end

    test "accepts {:neq, field, value}" do
      assert :ok = TxRetentionRules.validate_rule({:neq, :version, 1})
    end

    test "accepts {:gt, field, value}" do
      assert :ok = TxRetentionRules.validate_rule({:gt, :input_count, 0})
    end

    test "accepts {:gte, field, value}" do
      assert :ok = TxRetentionRules.validate_rule({:gte, :input_count, 3})
    end

    test "accepts {:lt, field, value}" do
      assert :ok = TxRetentionRules.validate_rule({:lt, :vsize, 1000})
    end

    test "accepts {:lte, field, value}" do
      assert :ok = TxRetentionRules.validate_rule({:lte, :output_count, 5})
    end

    test "accepts {:between, field, min, max}" do
      assert :ok = TxRetentionRules.validate_rule({:between, :base_size, 100, 500})
    end

    test "accepts {:in, field, values}" do
      assert :ok = TxRetentionRules.validate_rule({:in, :version, [1, 2]})
    end

    test "rejects unknown field" do
      assert {:error, _} = TxRetentionRules.validate_rule({:eq, :nonexistent_field, true})
    end

    test "rejects unknown operator" do
      assert {:error, _} = TxRetentionRules.validate_rule({:contains, :is_segwit, true})
    end

    test "rejects malformed scalar (missing value arg)" do
      assert {:error, _} = TxRetentionRules.validate_rule({:eq, :is_segwit})
    end

    test "rejects non-numeric value for :gt" do
      assert {:error, _} = TxRetentionRules.validate_rule({:gt, :input_count, "big"})
    end

    test "rejects non-numeric value for :gte" do
      assert {:error, _} = TxRetentionRules.validate_rule({:gte, :vsize, nil})
    end

    test "rejects non-numeric value for :lt" do
      assert {:error, _} = TxRetentionRules.validate_rule({:lt, :weight, :large})
    end

    test "rejects non-numeric value for :lte" do
      assert {:error, _} = TxRetentionRules.validate_rule({:lte, :output_count, "5"})
    end

    test "rejects non-numeric min in :between" do
      assert {:error, _} = TxRetentionRules.validate_rule({:between, :base_size, "small", 500})
    end

    test "rejects non-numeric max in :between" do
      assert {:error, _} = TxRetentionRules.validate_rule({:between, :base_size, 100, :big})
    end

    test "rejects inverted :between range (min > max)" do
      assert {:error, _} = TxRetentionRules.validate_rule({:between, :base_size, 500, 100})
    end
  end

  describe "validate_rule/1 — domain-specific predicates" do
    test "accepts {:has_output_script_type, type}" do
      assert :ok = TxRetentionRules.validate_rule({:has_output_script_type, :null_data})
    end

    test "accepts {:output_script_type_count_gte, type, n}" do
      assert :ok =
               TxRetentionRules.validate_rule({:output_script_type_count_gte, :p2_p_k_h, 2})
    end

    test "accepts {:has_any_output_script_type, [type, ...]}" do
      assert :ok =
               TxRetentionRules.validate_rule(
                 {:has_any_output_script_type, [:null_data, :non_standard]}
               )
    end

    test "accepts {:any_input_witness_items_eq, n}" do
      assert :ok = TxRetentionRules.validate_rule({:any_input_witness_items_eq, 1})
    end

    test "accepts {:any_input_witness_items_gte, n}" do
      assert :ok = TxRetentionRules.validate_rule({:any_input_witness_items_gte, 2})
    end

    test "accepts {:witness_total_items_gte, n}" do
      assert :ok = TxRetentionRules.validate_rule({:witness_total_items_gte, 4})
    end

    test "accepts {:witness_total_bytes_gte, n}" do
      assert :ok = TxRetentionRules.validate_rule({:witness_total_bytes_gte, 500})
    end

    test "accepts {:largest_witness_item_bytes_gte, n}" do
      assert :ok = TxRetentionRules.validate_rule({:largest_witness_item_bytes_gte, 100})
    end

    test "accepts {:distinct_output_script_types_gte, n}" do
      assert :ok = TxRetentionRules.validate_rule({:distinct_output_script_types_gte, 2})
    end

    test "rejects domain predicate with wrong arity" do
      assert {:error, _} = TxRetentionRules.validate_rule({:has_output_script_type})
    end

    test "rejects domain predicate with invalid type list" do
      assert {:error, _} =
               TxRetentionRules.validate_rule({:has_any_output_script_type, :not_a_list})
    end
  end

  # ---------------------------------------------------------------------------
  # match?/2 — boolean composition
  # ---------------------------------------------------------------------------

  describe "match?/2 — :all" do
    test "matches when all children match" do
      rule = {:all, [{:eq, :is_segwit, false}, {:gte, :input_count, 3}]}
      assert TxRetentionRules.match?(@legacy_details, rule)
    end

    test "does not match when one child fails" do
      rule = {:all, [{:eq, :is_segwit, false}, {:gte, :input_count, 99}]}
      refute TxRetentionRules.match?(@legacy_details, rule)
    end

    test "single-child :all works" do
      rule = {:all, [{:eq, :is_segwit, false}]}
      assert TxRetentionRules.match?(@legacy_details, rule)
    end
  end

  describe "match?/2 — :any" do
    test "matches when at least one child matches" do
      rule = {:any, [{:eq, :is_segwit, true}, {:gte, :input_count, 2}]}
      assert TxRetentionRules.match?(@legacy_details, rule)
    end

    test "does not match when no child matches" do
      rule = {:any, [{:eq, :is_segwit, true}, {:gte, :input_count, 99}]}
      refute TxRetentionRules.match?(@legacy_details, rule)
    end
  end

  describe "match?/2 — :not" do
    test "negates a matching rule" do
      rule = {:not, {:eq, :is_segwit, true}}
      assert TxRetentionRules.match?(@legacy_details, rule)
    end

    test "negates a non-matching rule" do
      rule = {:not, {:eq, :is_segwit, false}}
      refute TxRetentionRules.match?(@legacy_details, rule)
    end
  end

  describe "match?/2 — nested composition" do
    test "legacy multi-input rule matches the legacy fixture" do
      rule = {:all, [{:eq, :is_segwit, false}, {:gte, :input_count, 3}]}
      assert TxRetentionRules.match?(@legacy_details, rule)
    end

    test "legacy multi-input rule does not match segwit fixture" do
      rule = {:all, [{:eq, :is_segwit, false}, {:gte, :input_count, 3}]}
      refute TxRetentionRules.match?(@segwit_details, rule)
    end

    test "segwit + OP_RETURN rule matches op_return fixture when it is also segwit" do
      rule = {:all, [{:eq, :is_segwit, true}, {:has_output_script_type, :null_data}]}

      mixed =
        Map.merge(@segwit_details, %{
          has_op_return: true,
          output_script_types: [:p2_w_p_k_h, :null_data],
          output_script_type_counts: %{p2_w_p_k_h: 1, null_data: 1}
        })

      assert TxRetentionRules.match?(mixed, rule)
    end

    test "witness-heavy rule matches segwit fixture" do
      rule = {:any, [{:witness_total_bytes_gte, 200}, {:eq, :has_non_standard_output, true}]}
      assert TxRetentionRules.match?(@segwit_details, rule)
    end

    test "witness-heavy rule does not match legacy fixture" do
      rule = {:any, [{:witness_total_bytes_gte, 200}, {:eq, :has_non_standard_output, true}]}
      refute TxRetentionRules.match?(@legacy_details, rule)
    end
  end

  # ---------------------------------------------------------------------------
  # match?/2 — scalar comparisons
  # ---------------------------------------------------------------------------

  describe "match?/2 — :eq" do
    test "matches equal boolean" do
      assert TxRetentionRules.match?(@legacy_details, {:eq, :is_segwit, false})
    end

    test "does not match unequal boolean" do
      refute TxRetentionRules.match?(@legacy_details, {:eq, :is_segwit, true})
    end

    test "matches equal integer" do
      assert TxRetentionRules.match?(@legacy_details, {:eq, :version, 1})
    end
  end

  describe "match?/2 — :neq" do
    test "matches when values differ" do
      assert TxRetentionRules.match?(@legacy_details, {:neq, :version, 2})
    end

    test "does not match when values are equal" do
      refute TxRetentionRules.match?(@legacy_details, {:neq, :version, 1})
    end
  end

  describe "match?/2 — :gt / :gte / :lt / :lte" do
    test ":gt matches strictly greater" do
      assert TxRetentionRules.match?(@legacy_details, {:gt, :input_count, 2})
      refute TxRetentionRules.match?(@legacy_details, {:gt, :input_count, 3})
    end

    test ":gte matches equal and greater" do
      assert TxRetentionRules.match?(@legacy_details, {:gte, :input_count, 3})
      assert TxRetentionRules.match?(@legacy_details, {:gte, :input_count, 2})
      refute TxRetentionRules.match?(@legacy_details, {:gte, :input_count, 4})
    end

    test ":lt matches strictly less" do
      assert TxRetentionRules.match?(@legacy_details, {:lt, :input_count, 4})
      refute TxRetentionRules.match?(@legacy_details, {:lt, :input_count, 3})
    end

    test ":lte matches equal and less" do
      assert TxRetentionRules.match?(@legacy_details, {:lte, :input_count, 3})
      assert TxRetentionRules.match?(@legacy_details, {:lte, :input_count, 4})
      refute TxRetentionRules.match?(@legacy_details, {:lte, :input_count, 2})
    end
  end

  describe "match?/2 — :between" do
    test "matches when value is within inclusive range" do
      assert TxRetentionRules.match?(@legacy_details, {:between, :input_count, 1, 5})
      assert TxRetentionRules.match?(@legacy_details, {:between, :input_count, 3, 3})
    end

    test "does not match when value is outside range" do
      refute TxRetentionRules.match?(@legacy_details, {:between, :input_count, 4, 10})
      refute TxRetentionRules.match?(@legacy_details, {:between, :input_count, 1, 2})
    end
  end

  describe "match?/2 — numeric operators with absent fields" do
    # When validated: false, size fields (base_size, total_size, weight, vsize)
    # are not present in the details map. All numeric operators must return false
    # rather than silently producing wrong results from nil comparisons.
    @unvalidated_details Map.drop(@legacy_details, [:base_size, :total_size, :weight, :vsize])

    test ":gt returns false when field is absent" do
      refute TxRetentionRules.match?(@unvalidated_details, {:gt, :base_size, 0})
    end

    test ":gte returns false when field is absent" do
      refute TxRetentionRules.match?(@unvalidated_details, {:gte, :base_size, 0})
    end

    test ":lt returns false when field is absent" do
      refute TxRetentionRules.match?(@unvalidated_details, {:lt, :base_size, 9_999_999})
    end

    test ":lte returns false when field is absent" do
      refute TxRetentionRules.match?(@unvalidated_details, {:lte, :base_size, 9_999_999})
    end

    test ":between returns false when field is absent" do
      refute TxRetentionRules.match?(@unvalidated_details, {:between, :vsize, 0, 9_999_999})
    end
  end

  describe "match?/2 — :in" do
    test "matches when value is in the list" do
      assert TxRetentionRules.match?(@legacy_details, {:in, :version, [1, 2]})
    end

    test "does not match when value is not in the list" do
      refute TxRetentionRules.match?(@legacy_details, {:in, :version, [3, 4]})
    end
  end

  # ---------------------------------------------------------------------------
  # match?/2 — domain-specific predicates
  # ---------------------------------------------------------------------------

  describe "match?/2 — :has_output_script_type" do
    test "matches when the type is present in outputs" do
      assert TxRetentionRules.match?(@op_return_details, {:has_output_script_type, :null_data})
      assert TxRetentionRules.match?(@op_return_details, {:has_output_script_type, :p2_p_k_h})
    end

    test "does not match when the type is absent" do
      refute TxRetentionRules.match?(@legacy_details, {:has_output_script_type, :null_data})
    end
  end

  describe "match?/2 — :output_script_type_count_gte" do
    test "matches when count meets threshold" do
      assert TxRetentionRules.match?(
               @legacy_details,
               {:output_script_type_count_gte, :p2_p_k_h, 2}
             )
    end

    test "does not match when count is below threshold" do
      refute TxRetentionRules.match?(
               @legacy_details,
               {:output_script_type_count_gte, :p2_p_k_h, 3}
             )
    end

    test "type absent from counts is treated as 0" do
      refute TxRetentionRules.match?(
               @legacy_details,
               {:output_script_type_count_gte, :null_data, 1}
             )
    end
  end

  describe "match?/2 — :has_any_output_script_type" do
    test "matches when at least one type is present" do
      assert TxRetentionRules.match?(
               @op_return_details,
               {:has_any_output_script_type, [:null_data, :non_standard]}
             )
    end

    test "does not match when none of the types are present" do
      refute TxRetentionRules.match?(
               @legacy_details,
               {:has_any_output_script_type, [:null_data, :non_standard]}
             )
    end
  end

  describe "match?/2 — :any_input_witness_items_eq" do
    test "matches when some input has exactly that many items" do
      assert TxRetentionRules.match?(@segwit_details, {:any_input_witness_items_eq, 2})
    end

    test "does not match when no input has exactly that count" do
      refute TxRetentionRules.match?(@segwit_details, {:any_input_witness_items_eq, 3})
    end

    test "does not match on legacy tx" do
      refute TxRetentionRules.match?(@legacy_details, {:any_input_witness_items_eq, 0})
    end
  end

  describe "match?/2 — :any_input_witness_items_gte" do
    test "matches when some input has at least that many items" do
      assert TxRetentionRules.match?(@segwit_details, {:any_input_witness_items_gte, 2})
      assert TxRetentionRules.match?(@segwit_details, {:any_input_witness_items_gte, 1})
    end

    test "does not match when no input meets the threshold" do
      refute TxRetentionRules.match?(@segwit_details, {:any_input_witness_items_gte, 3})
    end
  end

  describe "match?/2 — :witness_total_items_gte" do
    test "matches when total items meet threshold" do
      assert TxRetentionRules.match?(@segwit_details, {:witness_total_items_gte, 4})
      assert TxRetentionRules.match?(@segwit_details, {:witness_total_items_gte, 3})
    end

    test "does not match when total items are below threshold" do
      refute TxRetentionRules.match?(@segwit_details, {:witness_total_items_gte, 5})
    end
  end

  describe "match?/2 — :witness_total_bytes_gte" do
    test "matches when total bytes meet threshold" do
      assert TxRetentionRules.match?(@segwit_details, {:witness_total_bytes_gte, 210})
      assert TxRetentionRules.match?(@segwit_details, {:witness_total_bytes_gte, 100})
    end

    test "does not match when total bytes are below threshold" do
      refute TxRetentionRules.match?(@segwit_details, {:witness_total_bytes_gte, 211})
    end
  end

  describe "match?/2 — :largest_witness_item_bytes_gte" do
    test "matches when largest item meets threshold" do
      assert TxRetentionRules.match?(@segwit_details, {:largest_witness_item_bytes_gte, 72})
      assert TxRetentionRules.match?(@segwit_details, {:largest_witness_item_bytes_gte, 50})
    end

    test "does not match when largest item is below threshold" do
      refute TxRetentionRules.match?(@segwit_details, {:largest_witness_item_bytes_gte, 73})
    end
  end

  describe "match?/2 — :distinct_output_script_types_gte" do
    test "matches when distinct type count meets threshold" do
      assert TxRetentionRules.match?(@op_return_details, {:distinct_output_script_types_gte, 2})
      assert TxRetentionRules.match?(@op_return_details, {:distinct_output_script_types_gte, 1})
    end

    test "does not match when distinct type count is below threshold" do
      refute TxRetentionRules.match?(@op_return_details, {:distinct_output_script_types_gte, 3})
    end

    test "counts only distinct types, not total outputs" do
      # @legacy_details has 2 p2_p_k_h outputs — still only 1 distinct type
      refute TxRetentionRules.match?(@legacy_details, {:distinct_output_script_types_gte, 2})
      assert TxRetentionRules.match?(@legacy_details, {:distinct_output_script_types_gte, 1})
    end

    test "matches threshold equal to the exact distinct count" do
      # @segwit_details has 1 distinct type (p2_w_p_k_h)
      assert TxRetentionRules.match?(@segwit_details, {:distinct_output_script_types_gte, 1})
    end
  end
end
