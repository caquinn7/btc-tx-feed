defmodule BtcTxFeed.StatsSessionsTest do
  use BtcTxFeed.DataCase, async: false

  alias BtcTxFeed.{Repo, StatsSession, StatsSessions}

  describe "create_open!/2" do
    test "inserts a row with started_at and decode_policy, returns a struct with an id" do
      policy = %{max_tx_size: 100_000, max_vin_count: 50}
      session = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], policy)

      assert session.id != nil
      assert session.started_at == ~U[2026-01-01 10:00:00Z]
      assert session.ended_at == nil
      assert session.counters == nil
    end

    test "persists the decode_policy blob" do
      policy = %{max_tx_size: 99_999, max_vin_count: 42}
      session = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], policy)

      row = Repo.get!(StatsSession, session.id)
      assert :erlang.binary_to_term(row.decode_policy) == policy
    end

    test "the row is visible in the database" do
      StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      assert Repo.aggregate(StatsSession, :count) == 1
    end
  end

  describe "finalize!/4" do
    test "updates ended_at, counters, and totals on the open row" do
      session = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      counters = %{total_decoded: 42, total_failed: 3}

      assert :ok =
               StatsSessions.finalize!(session.id, counters, ~U[2026-01-01 11:00:00Z], :shutdown)

      row = Repo.get!(StatsSession, session.id)
      assert row.ended_at == ~U[2026-01-01 11:00:00Z]
      assert row.total_decoded == 42
      assert row.total_failed == 3
      assert :erlang.binary_to_term(row.counters) == counters
    end
  end

  describe "create_open!/2 + finalize!/4 roundtrip" do
    test "a session can be opened and finalized end-to-end" do
      session = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      counters = %{{:version, 2} => 5, total_decoded: 5, total_failed: 1}

      StatsSessions.finalize!(session.id, counters, ~U[2026-01-01 11:00:00Z], :shutdown)

      retrieved = StatsSessions.get!(session.id)
      assert retrieved.started_at == ~U[2026-01-01 10:00:00Z]
      assert retrieved.ended_at == ~U[2026-01-01 11:00:00Z]
      assert retrieved.counters == counters
    end
  end

  describe "list/0" do
    test "returns empty list when no sessions" do
      assert StatsSessions.list() == []
    end

    test "excludes open sessions (ended_at IS NULL)" do
      StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      assert StatsSessions.list() == []
    end

    test "includes only finalized sessions" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 5, total_failed: 0},
        ~U[2026-01-01 11:00:00Z],
        :shutdown
      )

      assert length(StatsSessions.list()) == 1
    end

    test "returns sessions ordered by started_at desc" do
      s1 = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.finalize!(
        s1.id,
        %{total_decoded: 1, total_failed: 0},
        ~U[2026-01-01 11:00:00Z],
        :shutdown
      )

      s2 = StatsSessions.create_open!(~U[2026-01-02 10:00:00Z], %{})

      StatsSessions.finalize!(
        s2.id,
        %{total_decoded: 2, total_failed: 0},
        ~U[2026-01-02 11:00:00Z],
        :shutdown
      )

      [first, second] = StatsSessions.list()
      assert first.total_decoded == 2
      assert second.total_decoded == 1
    end

    test "does not include the counters blob" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 1, total_failed: 0},
        ~U[2026-01-01 11:00:00Z],
        :shutdown
      )

      [session] = StatsSessions.list()
      refute Map.has_key?(session, :counters)
    end

    test "includes id, started_at, ended_at, total_decoded, total_failed" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 7, total_failed: 2},
        ~U[2026-01-01 11:00:00Z],
        :shutdown
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
    test "returns a finalized session with deserialized counters map" do
      counters = %{total_decoded: 7, total_failed: 1, segwit_count: 4}
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      StatsSessions.finalize!(s.id, counters, ~U[2026-01-01 11:00:00Z], :shutdown)

      session = StatsSessions.get!(s.id)
      assert session.counters == counters
      assert session.total_decoded == 7
    end

    test "deserializes the decode_policy blob" do
      policy = %{max_tx_size: 50_000, max_vin_count: 10}
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], policy)

      session = StatsSessions.get!(s.id)
      assert session.decode_policy == policy
    end

    test "returns an open session with nil counters and deserialized decode_policy" do
      policy = %{max_tx_size: 400_000}
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], policy)

      session = StatsSessions.get!(s.id)
      assert session.ended_at == nil
      assert session.counters == nil
      assert session.decode_policy == policy
    end

    test "raises Ecto.NoResultsError for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        StatsSessions.get!(999_999)
      end
    end
  end

  describe "checkpoint!/2" do
    test "writes counters and totals without setting ended_at" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      counters = %{total_decoded: 10, total_failed: 2, segwit_count: 7}

      assert :ok = StatsSessions.checkpoint!(s.id, counters)

      row = Repo.get!(StatsSession, s.id)
      assert row.ended_at == nil
      assert row.total_decoded == 10
      assert row.total_failed == 2
      assert :erlang.binary_to_term(row.counters) == counters
    end

    test "defaults total_decoded and total_failed to 0 when keys are absent" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      assert :ok = StatsSessions.checkpoint!(s.id, %{segwit_count: 3})

      row = Repo.get!(StatsSession, s.id)
      assert row.total_decoded == 0
      assert row.total_failed == 0
    end

    test "can be called multiple times, overwriting previous checkpoint" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.checkpoint!(s.id, %{total_decoded: 5, total_failed: 0})
      StatsSessions.checkpoint!(s.id, %{total_decoded: 20, total_failed: 1})

      row = Repo.get!(StatsSession, s.id)
      assert row.total_decoded == 20
      assert row.total_failed == 1
      assert row.ended_at == nil
    end

    test "is a no-op on a finalized session" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 99, total_failed: 0},
        ~U[2026-01-01 11:00:00Z],
        :shutdown
      )

      assert :ok = StatsSessions.checkpoint!(s.id, %{total_decoded: 0, total_failed: 0})

      row = Repo.get!(StatsSession, s.id)
      assert row.total_decoded == 99
    end
  end

  describe "finalize!/4 with :startup_recovery" do
    test "sets end_reason to startup_recovery" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      assert :ok =
               StatsSessions.finalize!(
                 s.id,
                 %{total_decoded: 3, total_failed: 0},
                 ~U[2026-01-01 11:00:00Z],
                 :startup_recovery
               )

      row = Repo.get!(StatsSession, s.id)
      assert row.end_reason == "startup_recovery"
      assert row.ended_at == ~U[2026-01-01 11:00:00Z]
    end

    test "sets end_reason to shutdown for a normal shutdown" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 1, total_failed: 0},
        ~U[2026-01-01 11:00:00Z],
        :shutdown
      )

      row = Repo.get!(StatsSession, s.id)
      assert row.end_reason == "shutdown"
    end
  end

  describe "recover_orphans!/0" do
    test "returns 0 and does nothing when no open sessions exist" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      StatsSessions.finalize!(s.id, %{}, ~U[2026-01-01 11:00:00Z], :shutdown)

      assert StatsSessions.recover_orphans!() == 0
    end

    test "finalizes open sessions and returns the count" do
      StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      StatsSessions.create_open!(~U[2026-01-02 10:00:00Z], %{})

      assert StatsSessions.recover_orphans!() == 2
      assert length(StatsSessions.list()) == 2
    end

    test "recovered sessions have end_reason :startup_recovery" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.recover_orphans!()

      row = Repo.get!(StatsSession, s.id)
      assert row.end_reason == "startup_recovery"
    end

    test "uses checkpointed counters when available" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})
      counters = %{total_decoded: 15, total_failed: 1}
      StatsSessions.checkpoint!(s.id, counters)

      StatsSessions.recover_orphans!()

      row = Repo.get!(StatsSession, s.id)
      assert row.total_decoded == 15
      assert row.total_failed == 1
      assert :erlang.binary_to_term(row.counters) == counters
    end

    test "uses empty counters when no checkpoint exists" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.recover_orphans!()

      row = Repo.get!(StatsSession, s.id)
      assert row.total_decoded == 0
      assert row.total_failed == 0
    end

    test "does not affect already finalized sessions" do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z], %{})

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 99, total_failed: 0},
        ~U[2026-01-01 11:00:00Z],
        :shutdown
      )

      StatsSessions.recover_orphans!()

      row = Repo.get!(StatsSession, s.id)
      assert row.end_reason == "shutdown"
      assert row.total_decoded == 99
    end
  end
end
