defmodule BtcTxFeed.MempoolSocket do
  use GenServer

  require Logger

  alias BtcTxFeed.WebSocketClient

  defstruct [:socket, txids: [], retry_count: 0, ping_timer: nil]

  @mempool_url "wss://mempool.space/api/v1/ws"
  @subscription_frame ~s({"track-mempool-txids": true})

  # Client

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  # Server

  @impl GenServer
  def handle_call(:connected?, _from, state) do
    {:reply, WebSocketClient.connected?(state.socket), state}
  end

  @impl GenServer
  def init([]) do
    {:ok, %__MODULE__{}, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    # WebSocketClient.connect/1 is called from within this GenServer process,
    # so Mint registers self() as the socket's controlling process. The Erlang
    # runtime will deliver all incoming TCP/TLS data directly to this process's
    # mailbox as {:ssl, socket, data} messages, picked up by the catch-all
    # handle_info clause below.
    case WebSocketClient.connect(@mempool_url) do
      {:ok, client} ->
        Process.send_after(self(), :flush, 100)
        {:noreply, %{state | socket: client}}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        delay = backoff_delay(state.retry_count)
        Logger.info("Retrying in #{delay}ms (attempt #{state.retry_count + 1})")
        Process.send_after(self(), :connect, delay)
        {:noreply, %__MODULE__{retry_count: state.retry_count + 1}}
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
  def handle_info(:keepalive, state) do
    case WebSocketClient.send_frame(state.socket, {:ping, ""}) do
      {:ok, client} ->
        timer = Process.send_after(self(), :keepalive, 30_000)
        {:noreply, %{state | socket: client, ping_timer: timer}}

      {:error, _client, reason} ->
        Logger.error("Keepalive ping failed: #{inspect(reason)}")

        Phoenix.PubSub.broadcast(
          BtcTxFeed.PubSub,
          "mempool:status",
          {:socket_status, :disconnected}
        )

        Process.send_after(self(), :connect, backoff_delay(state.retry_count))
        {:noreply, %__MODULE__{retry_count: state.retry_count + 1}}
    end
  end

  @impl GenServer
  def handle_info(:connect, state) do
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)
    WebSocketClient.close(state.socket)
    {:noreply, %__MODULE__{retry_count: state.retry_count}, {:continue, :connect}}
  end

  @impl GenServer
  def handle_info(message, state) do
    case WebSocketClient.stream(state.socket, message) do
      {:ok, client, events} ->
        state = Enum.reduce(events, %{state | socket: client}, &handle_event(&2, &1))
        {:noreply, state}

      {:error, reason} ->
        Logger.error("Stream error: #{inspect(reason)}")
        if state.ping_timer, do: Process.cancel_timer(state.ping_timer)

        Phoenix.PubSub.broadcast(
          BtcTxFeed.PubSub,
          "mempool:status",
          {:socket_status, :disconnected}
        )

        Process.send_after(self(), :connect, backoff_delay(state.retry_count))
        {:noreply, %__MODULE__{retry_count: state.retry_count + 1}}

      :unknown ->
        {:noreply, state}
    end
  end

  defp handle_event(state, :connected) do
    Phoenix.PubSub.broadcast(BtcTxFeed.PubSub, "mempool:status", {:socket_status, :connected})

    case WebSocketClient.send_frame(state.socket, {:text, @subscription_frame}) do
      {:ok, client} ->
        timer = Process.send_after(self(), :keepalive, 30_000)
        %{state | socket: client, retry_count: 0, ping_timer: timer}

      {:error, _client, reason} ->
        raise "Failed to send subscription frame: #{inspect(reason)}"
    end
  end

  defp handle_event(state, {:text, text}) do
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
  end

  defp handle_event(state, {:close, reason}) do
    Logger.debug("Closing connection: #{inspect(reason)}")
    if state.ping_timer, do: Process.cancel_timer(state.ping_timer)

    Phoenix.PubSub.broadcast(
      BtcTxFeed.PubSub,
      "mempool:status",
      {:socket_status, :disconnected}
    )

    Process.send_after(self(), :connect, backoff_delay(state.retry_count))
    %__MODULE__{retry_count: state.retry_count + 1}
  end

  defp backoff_delay(retry_count) do
    base = min(1_000 * Integer.pow(2, retry_count), 30_000)
    jitter = trunc(base * 0.2 * (:rand.uniform() * 2 - 1))
    base + jitter
  end
end
