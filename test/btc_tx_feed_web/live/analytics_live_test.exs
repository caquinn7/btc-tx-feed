defmodule BtcTxFeedWeb.AnalyticsLiveTest do
  use BtcTxFeedWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BtcTxFeed.TxStats

  setup do
    sandbox_owner = Ecto.Adapters.SQL.Sandbox.start_owner!(BtcTxFeed.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox_owner) end)
    start_supervised!(TxStats)
    :ok
  end

  test "failures link includes the current session_id as a query param", %{conn: conn} do
    session_id = TxStats.get_session_id()
    {:ok, view, _html} = live(conn, ~p"/analytics")

    assert has_element?(view, "a[href='/analytics/failures/decode?session_id=#{session_id}']")
  end
end
