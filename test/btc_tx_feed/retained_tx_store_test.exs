defmodule BtcTxFeed.RetainedTxStoreTest do
  use BtcTxFeed.DataCase, async: false

  alias BtcTxFeed.{Repo, RetainedTransaction, RetainedTxStore}

  @raw_bytes <<0xDE, 0xAD, 0xBE, 0xEF>>
  @txid "deadbeef00000000000000000000000000000000000000000000000000000000"

  defp entry(opts \\ []) do
    %{
      code: Keyword.get(opts, :code, "F01"),
      label: Keyword.get(opts, :label, "OP_RETURN output present"),
      limit: Keyword.get(opts, :limit, 10),
      rule: Keyword.get(opts, :rule, {:has_output_script_type, :null_data})
    }
  end

  describe "insert/3" do
    test "inserts a row and returns :ok when under the limit" do
      assert :ok = RetainedTxStore.insert(@txid, @raw_bytes, entry())
      assert Repo.aggregate(RetainedTransaction, :count) == 1
    end

    test "does not insert when the code is at its limit" do
      e = entry(limit: 2)
      RetainedTxStore.insert(@txid, @raw_bytes, e)
      RetainedTxStore.insert(@txid <> "a", @raw_bytes, e)

      assert :ok = RetainedTxStore.insert(@txid <> "b", @raw_bytes, e)
      assert Repo.aggregate(RetainedTransaction, :count) == 2
    end

    test "stores corpus_code and corpus_label from the entry" do
      RetainedTxStore.insert(@txid, @raw_bytes, entry(code: "X99", label: "My label"))

      [row] = Repo.all(RetainedTransaction)
      assert row.corpus_code == "X99"
      assert row.corpus_label == "My label"
    end

    test "stores raw bytes as lowercase hex" do
      RetainedTxStore.insert(@txid, <<0xCA, 0xFE>>, entry())

      [row] = Repo.all(RetainedTransaction)
      assert row.raw_hex == "cafe"
    end

    test "stores matched_rule as inspect of the entry rule" do
      rule = {:has_output_script_type, :null_data}
      RetainedTxStore.insert(@txid, @raw_bytes, entry(rule: rule))

      [row] = Repo.all(RetainedTransaction)
      assert row.matched_rule == inspect(rule)
    end

    test "cap is per corpus_code, not global" do
      RetainedTxStore.insert(@txid, @raw_bytes, entry(code: "A01", limit: 1))
      RetainedTxStore.insert(@txid, @raw_bytes, entry(code: "B01", limit: 1))

      assert Repo.aggregate(RetainedTransaction, :count) == 2
    end

    test "second code is blocked independently when its limit is reached" do
      RetainedTxStore.insert(@txid, @raw_bytes, entry(code: "A01", limit: 1))
      RetainedTxStore.insert(@txid, @raw_bytes, entry(code: "A01", limit: 1))

      assert Repo.aggregate(RetainedTransaction, :count) == 1
    end
  end
end
