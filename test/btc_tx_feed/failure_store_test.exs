defmodule BtcTxFeed.FailureStoreTest do
  use BtcTxFeed.DataCase, async: false

  alias BtcTxFeed.{Failure, FailureStore, Repo, StatsSessions}

  defp open_session do
    StatsSessions.create_open!(DateTime.utc_now(), %{})
  end

  describe "insert/4" do
    test "persists a failure row with the given stats_session_id" do
      session = open_session()
      FailureStore.insert("abc123", <<1, 2, 3>>, :some_error, session.id)

      [failure] = Repo.all(Failure)
      assert failure.stats_session_id == session.id
      assert failure.txid == "abc123"
    end

    test "encodes raw bytes as lowercase hex" do
      session = open_session()
      FailureStore.insert(nil, <<0xDE, 0xAD, 0xBE, 0xEF>>, :err, session.id)

      [failure] = Repo.all(Failure)
      assert failure.raw_hex == "deadbeef"
    end

    test "stores error_reason as inspect string" do
      session = open_session()
      FailureStore.insert(nil, <<>>, {:decode_error, :bad_input}, session.id)

      [failure] = Repo.all(Failure)
      assert failure.error_reason == inspect({:decode_error, :bad_input})
    end
  end

  describe "list_for_session/1" do
    test "returns only failures belonging to the given session" do
      s1 = open_session()
      s2 = open_session()
      FailureStore.insert("tx1", <<1>>, :err, s1.id)
      FailureStore.insert("tx2", <<2>>, :err, s2.id)

      results = FailureStore.list_for_session(s1.id)
      assert length(results) == 1
      assert hd(results).txid == "tx1"
    end

    test "returns all failures for the session" do
      session = open_session()
      FailureStore.insert("tx1", <<1>>, :err, session.id)
      FailureStore.insert("tx2", <<2>>, :err, session.id)

      results = FailureStore.list_for_session(session.id)
      assert length(results) == 2
      txids = Enum.map(results, & &1.txid)
      assert "tx1" in txids
      assert "tx2" in txids
    end

    test "returns empty list when no failures for session" do
      session = open_session()
      assert FailureStore.list_for_session(session.id) == []
    end
  end
end
