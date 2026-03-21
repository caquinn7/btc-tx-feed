defmodule BtcTxFeedWeb.FailuresLiveTest do
  use BtcTxFeedWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BtcTxFeed.{FailureStore, StatsSessions}

  setup do
    sandbox_owner = Ecto.Adapters.SQL.Sandbox.start_owner!(BtcTxFeed.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox_owner) end)
    :ok
  end

  describe "without ?session_id param" do
    test "renders the failures container", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics/failures")
      assert has_element?(view, "#failures")
    end

    test "back link navigates to /analytics", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/analytics/failures")
      assert has_element?(view, "a[href='/analytics']")
    end
  end

  describe "with ?session_id for an open session" do
    setup do
      session = StatsSessions.create_open!(DateTime.utc_now())
      %{session: session}
    end

    test "renders the failures container", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/analytics/failures?session_id=#{session.id}")
      assert has_element?(view, "#failures")
    end

    test "back link navigates to /analytics for an open session", %{conn: conn, session: session} do
      {:ok, view, _html} = live(conn, ~p"/analytics/failures?session_id=#{session.id}")
      assert has_element?(view, "a[href='/analytics']")
    end

    test "only shows failures from the given session", %{conn: conn, session: session} do
      FailureStore.insert("tx-in-session", <<1>>, :err, session.id)

      other = StatsSessions.create_open!(DateTime.utc_now())
      FailureStore.insert("tx-other", <<2>>, :err, other.id)

      {:ok, view, _html} = live(conn, ~p"/analytics/failures?session_id=#{session.id}")

      html = render(view)
      assert html =~ "tx-in-session"
      refute html =~ "tx-other"
    end
  end

  describe "with ?session_id for a finalized session" do
    setup do
      s = StatsSessions.create_open!(~U[2026-01-01 10:00:00Z])

      StatsSessions.finalize!(
        s.id,
        %{total_decoded: 5, total_failed: 1},
        ~U[2026-01-01 11:00:00Z]
      )

      %{session_id: s.id}
    end

    test "renders the failures container", %{conn: conn, session_id: id} do
      {:ok, view, _html} = live(conn, ~p"/analytics/failures?session_id=#{id}")
      assert has_element?(view, "#failures")
    end

    test "back link navigates to /analytics/history/:id for a finalized session", %{
      conn: conn,
      session_id: id
    } do
      {:ok, view, _html} = live(conn, ~p"/analytics/failures?session_id=#{id}")
      assert has_element?(view, "a[href='/analytics/history/#{id}']")
    end
  end

  describe "with an invalid ?session_id param" do
    test "redirects to /analytics", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/analytics"}}} =
               live(conn, ~p"/analytics/failures?session_id=notanumber")
    end
  end
end
