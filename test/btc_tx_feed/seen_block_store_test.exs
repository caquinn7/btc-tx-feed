defmodule BtcTxFeed.SeenBlockStoreTest do
  use BtcTxFeed.DataCase, async: false

  alias BtcTxFeed.SeenBlockStore

  @hash "000000000000000000021234abcdef000000000000000000000000000000aaaa"
  @hash2 "000000000000000000021234abcdef000000000000000000000000000000bbbb"

  describe "all_hashes/0" do
    test "returns an empty MapSet when no blocks have been seen" do
      assert SeenBlockStore.all_hashes() == MapSet.new()
    end

    test "returns a MapSet containing all stored hashes" do
      SeenBlockStore.insert!(@hash)
      SeenBlockStore.insert!(@hash2)

      assert SeenBlockStore.all_hashes() == MapSet.new([@hash, @hash2])
    end
  end

  describe "insert!/1" do
    test "returns :ok" do
      assert :ok = SeenBlockStore.insert!(@hash)
    end

    test "persists the hash so it appears in all_hashes/0" do
      SeenBlockStore.insert!(@hash)

      assert MapSet.member?(SeenBlockStore.all_hashes(), @hash)
    end

    test "is idempotent — inserting the same hash twice does not raise or duplicate" do
      SeenBlockStore.insert!(@hash)
      assert :ok = SeenBlockStore.insert!(@hash)

      assert SeenBlockStore.all_hashes() == MapSet.new([@hash])
    end
  end
end
