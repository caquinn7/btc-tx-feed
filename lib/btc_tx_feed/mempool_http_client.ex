defmodule BtcTxFeed.MempoolHttpClient do
  def get_raw_tx(txid) do
    case Req.get("https://mempool.space/api/tx/#{txid}/raw") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, ex} -> {:error, ex}
    end
  end

  def get_recent_blocks do
    case Req.get("https://mempool.space/api/blocks") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, ex} -> {:error, ex}
    end
  end

  def get_block_txid(block_hash, index) do
    case Req.get("https://mempool.space/api/block/#{block_hash}/txid/#{index}",
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, ex} -> {:error, ex}
    end
  end
end
