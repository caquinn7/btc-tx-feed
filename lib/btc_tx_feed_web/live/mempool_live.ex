defmodule BtcTxFeedWeb.MempoolLive do
  use BtcTxFeedWeb, :live_view

  import BtcTxFeedWeb.TxComponents

  alias BtcTxFeed.{MempoolHttpClient, MempoolSocket, TxParser}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(BtcTxFeed.PubSub, "mempool:txids")
        Phoenix.PubSub.subscribe(BtcTxFeed.PubSub, "mempool:status")
        assign(socket, :connected, MempoolSocket.connected?())
      else
        assign(socket, :connected, false)
      end

    socket =
      socket
      |> stream(:txids, [])
      |> assign(:selected_txid, nil)
      |> assign(:tx_details, nil)
      |> assign(:task_ref, nil)

    {:ok, socket}
  end

  # `ref` guard ensures only the current task's result is handled,
  # not an older orphaned one if the user clicks a second txid
  # before the first resolves
  @impl true
  def handle_info({ref, result}, socket) when ref == socket.assigns.task_ref do
    # clean up the monitor so the `:DOWN` msg (sent when the task process exits)
    # doesn't land in the mailbox afterward
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(:tx_details, result)
      |> assign(:task_ref, nil)

    {:noreply, socket}
  end

  # Catches two cases:
  # 1. A `:DOWN` that arrived before `Process.demonitor(ref, [:flush])` could
  #    suppress it (unavoidable race between task completion and demonitor).
  # 2. `:DOWN` messages from orphaned tasks whose refs were replaced when the
  #    user clicked a new txid — those tasks still run to completion but their
  #    results are intentionally ignored.
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:socket_status, status}, socket) do
    {:noreply, assign(socket, :connected, status == :connected)}
  end

  @impl true
  def handle_info({:new_txids, txids}, socket) do
    socket =
      txids
      |> Enum.map(&%{id: &1, txid: &1})
      |> Enum.reduce(socket, &stream_insert(&2, :txids, &1, at: 0, limit: 10))

    {:noreply, socket}
  end

  @impl true
  def handle_event("clicked_txid", %{"txid" => txid}, socket) do
    task =
      Task.async(fn ->
        case MempoolHttpClient.get_raw_tx(txid) do
          {:ok, raw} ->
            case TxParser.parse(raw) do
              {:ok, details} -> {:ok, details, Base.encode16(raw, case: :lower)}
              err -> err
            end

          {:error, reason} ->
            {:error, reason}
        end
      end)

    socket =
      socket
      |> assign(:selected_txid, txid)
      |> assign(:tx_details, :loading)
      |> assign(:task_ref, task.ref)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/"}>
      <%!-- 7.5rem = header 4rem + main pt-6 1.5rem + layout pb-8 2rem --%>
      <div class="flex flex-col h-[calc(100vh-7.5rem)]">
        <%!-- Page header --%>
        <div class="mb-8">
          <div class="flex items-center gap-3 mb-1">
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
            <p class="text-base-content">
              New transactions entering the Bitcoin mempool in real time.
            </p>
          </div>
        </div>

        <%!-- Two-column layout --%>
        <div class="flex gap-6 flex-1 min-h-0 overflow-hidden">
          <%!-- Left column: txid list --%>
          <div class="w-2/5 shrink-0 flex flex-col overflow-y-auto min-h-0">
            <%!-- Stats bar --%>
            <div class="flex items-center justify-between mb-4 text-xs text-base-content/40 font-mono">
              <span>Click a txid to inspect it</span>
            </div>

            <%!-- Transaction list --%>
            <div id="transactions" phx-update="stream" class="flex flex-col gap-1">
              <%!-- Empty state (only shown when stream is empty) --%>
              <div
                id="txids-empty-state"
                class="hidden only:block text-center text-sm text-base-content/40 py-16"
              >
                Waiting for transactions…
              </div>
              <div
                :for={{id, tx} <- @streams.txids}
                id={id}
                phx-click="clicked_txid"
                phx-value-txid={tx.txid}
                class={[
                  "group flex items-center gap-3 rounded-lg border px-4 py-3 transition-colors cursor-pointer",
                  if(tx.txid == @selected_txid,
                    do: "border-orange-500/40 bg-orange-500/10 ring-1 ring-orange-500/20",
                    else: "border-base-300 bg-base-200 hover:bg-base-300"
                  )
                ]}
              >
                <span class={[
                  "font-mono text-sm truncate transition-colors",
                  if(tx.txid == @selected_txid,
                    do: "text-base-content",
                    else: "text-base-content/80 group-hover:text-base-content"
                  )
                ]}>
                  {tx.txid}
                </span>
                <.icon
                  name="hero-arrow-right-circle"
                  class={[
                    "size-4 shrink-0 ml-auto transition-colors",
                    if(tx.txid == @selected_txid,
                      do: "text-orange-400",
                      else: "text-orange-400/50 group-hover:text-orange-400"
                    )
                  ]}
                />
              </div>
            </div>
          </div>

          <%!-- Right column: details panel --%>
          <div class="flex-1 min-w-0 min-h-0 flex flex-col pt-8">
            <div class="flex-1 min-h-0 overflow-y-auto">
              <%= cond do %>
                <% @tx_details == nil -> %>
                  <div
                    id="tx-empty-state"
                    class="flex flex-col items-center h-full py-32 text-center"
                  >
                    <div class="rounded-full bg-base-200 p-6 mb-4">
                      <.icon name="hero-magnifying-glass" class="size-8 text-base-content/20" />
                    </div>
                    <p class="text-sm font-medium text-base-content/40">
                      Select a txid to inspect the transaction
                    </p>
                  </div>
                <% @tx_details == :loading -> %>
                  <div id="tx-loading-state" class="rounded-xl border border-base-300 bg-base-200 p-6">
                    <div class="flex items-center gap-3 mb-4">
                      <div class="size-4 rounded-full border-2 border-orange-400/30 border-t-orange-400 animate-spin shrink-0" />
                      <span class="text-sm text-base-content/60">Decoding transaction…</span>
                    </div>
                    <p class="font-mono text-xs text-base-content/40 break-all mb-6">
                      {@selected_txid}
                    </p>
                    <div class="space-y-2.5 animate-pulse">
                      <div class="h-3 bg-base-300 rounded w-full" />
                      <div class="h-3 bg-base-300 rounded w-4/5" />
                      <div class="h-3 bg-base-300 rounded w-3/5" />
                      <div class="h-3 bg-base-300 rounded w-full" />
                      <div class="h-3 bg-base-300 rounded w-2/3" />
                    </div>
                  </div>
                <% match?({:error, _}, @tx_details) -> %>
                  <div
                    id="tx-error-state"
                    class="rounded-xl border border-red-500/20 bg-red-500/5 p-6"
                  >
                    <div class="flex items-center gap-3 mb-3">
                      <.icon name="hero-exclamation-triangle" class="size-5 text-red-400 shrink-0" />
                      <span class="text-sm font-semibold text-red-400">
                        Failed to load transaction
                      </span>
                    </div>
                    <p class="font-mono text-xs text-base-content/40 break-all mb-3">
                      txid {@selected_txid}
                    </p>
                    <p class="font-mono text-xs text-base-content/50 break-all">
                      {inspect(elem(@tx_details, 1))}
                    </p>
                  </div>
                <% true -> %>
                  <.tx_details_card details={elem(@tx_details, 1)} raw_hex={elem(@tx_details, 2)} />
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
