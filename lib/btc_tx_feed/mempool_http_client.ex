defmodule BtcTxFeed.MempoolHttpClient do
  def get_raw_tx(txid) do
    case Req.get("https://mempool.space/api/tx/#{txid}/raw") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, ex} -> {:error, ex}
    end
  end
end
