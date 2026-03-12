defmodule BtcTxFeed.MempoolSocket do
  use GenServer

  require Logger
  require Mint.HTTP

  @dialyzer {:nowarn_function, [handle_response: 2, send_frame: 2]}

  defstruct [
    :conn,
    :websocket,
    :request_ref,
    :status,
    :resp_headers,
    txids: []
  ]

  # Client

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Server

  @impl GenServer
  def init([]) do
    {:ok, %__MODULE__{}, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    uri = URI.parse("wss://mempool.space/api/v1/ws")

    # Mint.HTTP.connect/4 is called from within this GenServer process, so Mint
    # registers self() as the socket's controlling process. From this point on,
    # the Erlang runtime delivers all incoming TCP/TLS socket data directly to
    # this process's mailbox as {:ssl, socket, data} messages, which are picked
    # up by the catch-all handle_info(message, state) clause below.
    with {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, uri.port, protocols: [:http1]),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(:wss, conn, uri.path, []) do
      Process.send_after(self(), :flush, 100)
      {:noreply, %{state | conn: conn, request_ref: ref}}
    else
      {:error, _conn, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:stop, reason, state}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:stop, reason, state}
    end
  end

  @impl GenServer
  def handle_info(:flush, %{txids: []} = state) do
    Process.send_after(self(), :flush, 100)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    Phoenix.PubSub.broadcast(BtcTxFeed.PubSub, "mempool:txids", {:new_txids, state.txids})
    Process.send_after(self(), :flush, 100)
    {:noreply, %{state | txids: []}}
  end

  @impl GenServer
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state =
          Enum.reduce(responses, %{state | conn: conn}, &handle_response(&2, &1))

        {:noreply, state}

      {:error, _conn, reason, _responses} ->
        Logger.error("Stream error: #{inspect(reason)}")
        send(self(), :connect)
        {:noreply, %__MODULE__{}}

      :unknown ->
        {:noreply, state}
    end
  end

  # Binding `ref` in both the struct pattern and the response tuple is an equality
  # constraint — the clause only matches when `state.request_ref == ref` in the tuple.
  defp handle_response(%{request_ref: ref} = state, {:status, ref, status}) do
    %{state | status: status}
  end

  defp handle_response(%{request_ref: ref} = state, {:headers, ref, resp_headers}) do
    %{state | resp_headers: resp_headers}
  end

  defp handle_response(%{request_ref: ref} = state, {:done, ref}) do
    case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
      {:ok, conn, websocket} ->
        state = %{state | conn: conn, websocket: websocket}

        case send_frame(state, {:text, ~s({"track-mempool-txids": true})}) do
          {:ok, state} ->
            state

          {:error, _state, reason} ->
            raise "Failed to send subscription frame: #{inspect(reason)}"
        end

      {:error, conn, reason} ->
        Logger.error("WebSocket upgrade failed: #{inspect(reason)}")
        %{state | conn: conn}
    end
  end

  defp handle_response(%{request_ref: ref, websocket: websocket} = state, {:data, ref, data})
       when not is_nil(websocket) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        %{state | websocket: websocket}
        |> handle_frames(frames)

      {:error, websocket, reason} ->
        Logger.debug("Error decoding data: #{inspect(reason)}")
        %{state | websocket: websocket}
    end
  end

  defp handle_response(state, _response), do: state

  defp handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      {:close, _code, reason}, _state ->
        Logger.debug("Closing connection: #{inspect(reason)}")
        send(self(), :connect)
        %__MODULE__{}

      {:text, text}, state ->
        Logger.debug("Received: #{inspect(text)}")

        case Jason.decode(text) do
          {:ok, %{"mempool-txids" => %{"added" => txids}}} when is_list(txids) ->
            %{state | txids: txids ++ state.txids}

          {:ok, _} ->
            state

          {:error, reason} ->
            Logger.warning("Failed to decode WebSocket message: #{inspect(reason)}")
            state
        end

      frame, state ->
        Logger.debug("Unexpected frame received: #{inspect(frame)}")
        state
    end)
  end

  defp send_frame(state, frame) do
    case Mint.WebSocket.encode(state.websocket, frame) do
      {:ok, websocket, data} ->
        state = %{state | websocket: websocket}

        case Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
          {:ok, conn} -> {:ok, %{state | conn: conn}}
          {:error, conn, reason} -> {:error, %{state | conn: conn}, reason}
        end

      {:error, websocket, reason} ->
        {:error, %{state | websocket: websocket}, reason}
    end
  end
end
