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
  end

  describe "terminate/2" do
    test "archives a session row to the database on shutdown" do
      start_supervised!(TxStats)

      TxStats.record(base_details())
      TxStats.record_failure()

      stop_supervised!(TxStats)

      sessions = Repo.all(StatsSession)
      assert length(sessions) == 1
    end

    test "archives correct decoded and failed totals" do
      start_supervised!(TxStats)

      TxStats.record(base_details())
      TxStats.record(base_details())
      TxStats.record_failure()

      stop_supervised!(TxStats)

      [session] = Repo.all(StatsSession)
      assert session.total_decoded == 2
      assert session.total_failed == 1
    end

    test "archived session has ended_at set" do
      start_supervised!(TxStats)

      stop_supervised!(TxStats)

      [session] = Repo.all(StatsSession)
      assert session.ended_at != nil
    end

    test "archived counters blob round-trips to a map" do
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
