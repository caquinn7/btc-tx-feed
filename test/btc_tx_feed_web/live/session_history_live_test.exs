defmodule BtcTxFeedWeb.SessionHistoryLiveTest do
  use BtcTxFeedWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BtcTxFeed.StatsSessions

  setup do
    sandbox_owner =
      Ecto.Adapters.SQL.Sandbox.start_owner!(BtcTxFeed.Repo, shared: true)

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox_owner) end)
    :ok
  end

  describe "list view (/analytics/history)" do
    test "renders the sessions table", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics/history")

      assert has_element?(view, "#sessions-table")
    end

    test "shows empty state when no sessions exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics/history")

      assert has_element?(view, "#sessions-table td", "No sessions recorded yet.")
    end

    test "renders a row for each archived session", %{conn: conn} do
      s1 = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z])

      StatsSessions.finalize!(
        s1.id,
        %{total_decoded: 10, total_failed: 2},
        ~U[2026-01-01 11:00:00Z]
      )

      s2 = StatsSessions.create_open!(~U[2026-01-02 10:00:00Z])

      StatsSessions.finalize!(
        s2.id,
        %{total_decoded: 5, total_failed: 0},
        ~U[2026-01-02 11:00:00Z]
      )

      {:ok, view, _html} = live(conn, ~p"/analytics/history")

      assert has_element?(view, "[id^='session-row-']")
      assert view |> element("#sessions-table") |> render() =~ "10"
    end

    test "session rows link to the detail view", %{conn: conn} do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z])

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 3, total_failed: 0},
        ~U[2026-01-01 11:00:00Z]
      )

      {:ok, view, _html} = live(conn, ~p"/analytics/history")
      [%{id: id}] = BtcTxFeed.Repo.all(BtcTxFeed.StatsSession)

      assert has_element?(view, "#session-row-#{id}")
    end
  end

  describe "detail view (/analytics/history/:id)" do
    setup do
      counters = %{
        {:vsize_bucket, :tiny} => 40,
        {:input_bucket, :single} => 50,
        {:output_bucket, :few} => 30,
        {:version, 2} => 50,
        {:script_type, :p2_w_p_k_h} => 50,
        total_decoded: 50,
        total_failed: 5,
        segwit_count: 30,
        legacy_count: 20
      }

      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z])
      StatsSessions.finalize!(s.id, counters, ~U[2026-01-01 11:00:00Z])
      [%{id: id}] = BtcTxFeed.StatsSessions.list()
      %{session_id: id}
    end

    test "renders all stat section cards", %{conn: conn, session_id: id} do
      {:ok, view, _html} = live(conn, ~p"/analytics/history/#{id}")

      assert has_element?(view, "#stats-pass-rate")
      assert has_element?(view, "#stats-tx-type")
      assert has_element?(view, "#stats-vsize")
      assert has_element?(view, "#stats-script-types")
      assert has_element?(view, "#stats-version-histogram")
      assert has_element?(view, "#stats-io-buckets")
    end

    test "renders the back to history link", %{conn: conn, session_id: id} do
      {:ok, view, _html} = live(conn, ~p"/analytics/history/#{id}")

      assert has_element?(view, "a[href='/analytics/history']")
    end

    test "displays decoded and failed totals from the archived counters", %{
      conn: conn,
      session_id: id
    } do
      {:ok, view, _html} = live(conn, ~p"/analytics/history/#{id}")

      pass_rate_html = view |> element("#stats-pass-rate") |> render()
      assert pass_rate_html =~ "50"
      assert pass_rate_html =~ "5"
    end

    test "renders a failures link with the correct session_id", %{conn: conn, session_id: id} do
      {:ok, view, _html} = live(conn, ~p"/analytics/history/#{id}")

      assert has_element?(view, "a[href='/analytics/failures?session_id=#{id}']")
    end
  end
end
