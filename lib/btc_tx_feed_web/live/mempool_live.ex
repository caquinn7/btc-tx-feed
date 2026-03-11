defmodule BtcTxFeedWeb.MempoolLive do
  use BtcTxFeedWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(BtcTxFeed.PubSub, "mempool:txids")
        assign(socket, :connected, true)
      else
        assign(socket, :connected, false)
      end

    socket =
      socket
      |> assign(:txids, [])
      |> assign(:tx_count, 0)
      |> stream(:txids, [])

    {:ok, socket}
  end

  @impl true
  def handle_info({:new_txids, txids}, socket) do
    updated_txids =
      txids
      |> Enum.map(fn txid -> %{id: txid, txid: txid} end)
      |> Enum.concat(socket.assigns.txids)
      |> Enum.take(50)

    socket =
      socket
      |> stream(:txids, updated_txids, reset: true)
      |> assign(:txids, updated_txids)
      |> assign(:tx_count, length(updated_txids))

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <%!-- Page header --%>
      <div class="mb-8">
        <div class="flex items-center gap-3 mb-1">
          <h1 class="text-2xl font-bold tracking-tight">Live Mempool Feed</h1>
          <span class={[
            "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium",
            if(@connected,
              do: "bg-green-500/15 text-green-400",
              else: "bg-yellow-500/15 text-yellow-400"
            )
          ]}>
            <span class={[
              "size-1.5 rounded-full",
              if(@connected, do: "bg-green-400 animate-pulse", else: "bg-yellow-400")
            ]} />
            {if @connected, do: "Live", else: "Connecting…"}
          </span>
        </div>
        <p class="text-sm text-base-content/50">
          New transactions entering the Bitcoin mempool in real time.
        </p>
      </div>

      <%!-- Stats bar --%>
      <div class="flex items-center justify-between mb-4 text-xs text-base-content/40 font-mono">
        <span>{@tx_count} transactions</span>
        <span>Click a txid to inspect it</span>
      </div>

      <%!-- Transaction list --%>
      <div
        id="transactions"
        phx-update="stream"
        class="flex flex-col gap-1"
      >
        <div
          :for={{id, tx} <- @streams.txids}
          id={id}
          class="group flex items-center gap-3 rounded-lg border border-base-300 bg-base-200 px-4 py-3 hover:bg-base-300 transition-colors cursor-pointer"
        >
          <.icon name="hero-arrow-right-circle" class="size-4 text-orange-400 shrink-0" />
          <span class="font-mono text-sm truncate text-base-content/80 group-hover:text-base-content transition-colors">
            {tx.txid}
          </span>
          <.icon name="hero-chevron-right" class="size-4 text-base-content/20 shrink-0 ml-auto" />
        </div>
      </div>

      <%!-- Empty state (only shown when stream is empty) --%>
      <p
        :if={@tx_count == 0}
        class="text-center text-sm text-base-content/40 py-16"
      >
        Waiting for transactions…
      </p>
    </Layouts.app>
    """
  end
end
