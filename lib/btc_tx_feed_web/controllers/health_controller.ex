defmodule BtcTxFeedWeb.HealthController do
  use BtcTxFeedWeb, :controller

  def check(conn, _params) do
    send_resp(conn, 200, "ok")
  end
end
