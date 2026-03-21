defmodule BtcTxFeed.StatsSessionsTest do
  use BtcTxFeed.DataCase, async: false

  alias BtcTxFeed.{Repo, StatsSession, StatsSessions}

  describe "archive/3" do
    test "inserts a stats_sessions row" do
      counters = %{total_decoded: 42, total_failed: 3}

      assert :ok =
               StatsSessions.archive(counters, ~U[2026-01-01 10:00:00Z], ~U[2026-01-01 11:00:00Z])

      assert Repo.aggregate(StatsSession, :count) == 1
    end

    test "stores denormalized totals" do
      counters = %{total_decoded: 10, total_failed: 2}
      StatsSessions.archive(counters, ~U[2026-01-01 10:00:00Z], ~U[2026-01-01 11:00:00Z])

      [session] = Repo.all(StatsSession)
      assert session.total_decoded == 10
      assert session.total_failed == 2
    end

    test "stores counters blob that round-trips" do
      counters = %{{:version, 2} => 5, total_decoded: 5, total_failed: 1}
      StatsSessions.archive(counters, ~U[2026-01-01 10:00:00Z], ~U[2026-01-01 11:00:00Z])

      [session] = Repo.all(StatsSession)
      assert :erlang.binary_to_term(session.counters) == counters
    end

    test "stores started_at and ended_at" do
      started_at = ~U[2026-01-01 10:00:00Z]
      ended_at = ~U[2026-01-01 11:30:00Z]
      StatsSessions.archive(%{total_decoded: 0, total_failed: 0}, started_at, ended_at)

      [session] = Repo.all(StatsSession)
      assert session.started_at == started_at
      assert session.ended_at == ended_at
    end
  end

  describe "list/0" do
    test "returns empty list when no sessions" do
      assert StatsSessions.list() == []
    end

    test "returns sessions ordered by started_at desc" do
      StatsSessions.archive(
        %{total_decoded: 1, total_failed: 0},
        ~U[2026-01-01 10:00:00Z],
        ~U[2026-01-01 11:00:00Z]
      )

      StatsSessions.archive(
        %{total_decoded: 2, total_failed: 0},
        ~U[2026-01-02 10:00:00Z],
        ~U[2026-01-02 11:00:00Z]
      )

      [first, second] = StatsSessions.list()
      assert first.total_decoded == 2
      assert second.total_decoded == 1
    end

    test "does not include the counters blob" do
      StatsSessions.archive(
        %{total_decoded: 1, total_failed: 0},
        ~U[2026-01-01 10:00:00Z],
        ~U[2026-01-01 11:00:00Z]
      )

      [session] = StatsSessions.list()
      refute Map.has_key?(session, :counters)
    end

    test "includes id, started_at, ended_at, total_decoded, total_failed" do
      StatsSessions.archive(
        %{total_decoded: 7, total_failed: 2},
        ~U[2026-01-01 10:00:00Z],
        ~U[2026-01-01 11:00:00Z]
      )

      [session] = StatsSessions.list()
      assert Map.has_key?(session, :id)
      assert Map.has_key?(session, :started_at)
      assert Map.has_key?(session, :ended_at)
      assert session.total_decoded == 7
      assert session.total_failed == 2
    end
  end

  describe "get!/1" do
    test "returns session with deserialized counters map" do
      counters = %{total_decoded: 7, total_failed: 1, segwit_count: 4}

      StatsSessions.archive(counters, ~U[2026-01-01 10:00:00Z], ~U[2026-01-01 11:00:00Z])

      %{id: id} = Repo.one!(StatsSession)
      session = StatsSessions.get!(id)

      assert session.counters == counters
      assert session.total_decoded == 7
    end

    test "raises Ecto.NoResultsError for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        StatsSessions.get!(999_999)
      end
    end
  end
end
