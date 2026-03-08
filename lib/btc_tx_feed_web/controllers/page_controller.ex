defmodule BtcTxFeedWeb.PageController do
  use BtcTxFeedWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
