defmodule BtcTxFeed.TxStatsSessionTest do
  use ExUnit.Case, async: false

  alias BtcTxFeed.{Repo, StatsSession, TxStats}

  setup do
    sandbox_owner =
      Ecto.Adapters.SQL.Sandbox.start_owner!(BtcTxFeed.Repo, shared: true)

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox_owner) end)
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

  describe "init/1" do
    test "ETS starts empty regardless of prior state" do
      start_supervised!(TxStats)
      assert TxStats.get() == %{}
    end

    test "creates an open session row in the database" do
      start_supervised!(TxStats)
      assert Repo.aggregate(StatsSession, :count) == 1
      [session] = Repo.all(StatsSession)
      assert session.ended_at == nil
    end

    test "stores the decode_policy snapshot in the session row" do
      start_supervised!(TxStats)
      [session] = Repo.all(StatsSession)
      assert session.decode_policy != nil
      policy = :erlang.binary_to_term(session.decode_policy)
      assert is_map(policy)
      assert Map.has_key?(policy, :max_tx_size)
    end
  end

  describe "get_session_id/0" do
    test "returns the DB row id of the current open session" do
      start_supervised!(TxStats)
      [session] = Repo.all(StatsSession)
      assert TxStats.get_session_id() == session.id
    end
  end

  describe "terminate/2" do
    test "finalizes the session row in the database on shutdown" do
      start_supervised!(TxStats)

      TxStats.record(base_details())
      TxStats.record_failure()

      stop_supervised!(TxStats)

      assert length(Repo.all(StatsSession)) == 1
    end

    test "finalizes correct decoded and failed totals" do
      start_supervised!(TxStats)

      TxStats.record(base_details())
      TxStats.record(base_details())
      TxStats.record_failure()

      stop_supervised!(TxStats)

      [session] = Repo.all(StatsSession)
      assert session.total_decoded == 2
      assert session.total_failed == 1
    end

    test "finalized session has ended_at set" do
      start_supervised!(TxStats)

      stop_supervised!(TxStats)

      [session] = Repo.all(StatsSession)
      assert session.ended_at != nil
    end

    test "finalized counters blob round-trips to a map" do
      start_supervised!(TxStats)

      TxStats.record(base_details(%{is_segwit: true}))

      stop_supervised!(TxStats)

      [session] = Repo.all(StatsSession)
      counters = :erlang.binary_to_term(session.counters)
      assert is_map(counters)
      assert counters[:segwit_count] == 1
    end
  end
end
