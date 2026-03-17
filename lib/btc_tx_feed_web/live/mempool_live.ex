defmodule BtcTxFeedWeb.MempoolLive do
  use BtcTxFeedWeb, :live_view

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
          {:ok, raw} -> TxParser.parse(raw)
          {:error, reason} -> {:error, reason}
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
                  <.tx_details_card details={elem(@tx_details, 1)} />
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp tx_details_card(assigns) do
    ~H"""
    <div id="tx-details" class="rounded-xl border border-base-300 bg-base-200 overflow-hidden">
      <%!-- Header: badges + txid/wtxid --%>
      <div class="px-6 py-5 border-b border-base-300">
        <div class="flex items-center gap-2 flex-wrap mb-3">
          <%= if @details.is_segwit do %>
            <span class="inline-flex items-center rounded-full bg-blue-500/15 px-2.5 py-0.5 text-xs font-semibold text-blue-400">
              SegWit
            </span>
          <% end %>
          <%= if @details.has_coinbase_marker do %>
            <span class="inline-flex items-center rounded-full bg-yellow-500/15 px-2.5 py-0.5 text-xs font-semibold text-yellow-400">
              Coinbase
            </span>
          <% end %>
          <%= if not @details.is_segwit and not @details.has_coinbase_marker do %>
            <span class="inline-flex items-center rounded-full bg-base-300 px-2.5 py-0.5 text-xs font-medium text-base-content/50">
              Legacy
            </span>
          <% end %>
        </div>
        <%= if Map.has_key?(@details, :txid) do %>
          <p class="font-mono text-xs text-base-content/60 break-all leading-relaxed">
            <span class="text-[10px] text-base-content/30 mr-2 select-none">txid</span>{@details.txid}
          </p>
        <% end %>
        <%= if Map.has_key?(@details, :wtxid) and @details.is_segwit do %>
          <p class="font-mono text-xs text-base-content/40 break-all leading-relaxed mt-1">
            <span class="text-[10px] text-base-content/20 mr-2 select-none">wtxid</span>{@details.wtxid}
          </p>
        <% end %>
      </div>

      <div class="p-6 space-y-8">
        <%!-- Overview grid --%>
        <div>
          <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/30 mb-3">
            Overview
          </h3>
          <dl class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
              <dt class="text-xs text-base-content/40 mb-0.5">Version</dt>
              <dd class="text-sm font-mono font-medium">{@details.version}</dd>
            </div>
            <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
              <dt class="text-xs text-base-content/40 mb-0.5">Lock Time</dt>
              <dd class="text-sm font-mono font-medium">{@details.lock_time}</dd>
            </div>
            <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
              <dt class="text-xs text-base-content/40 mb-0.5">Inputs</dt>
              <dd class="text-sm font-mono font-medium">{@details.input_count}</dd>
            </div>
            <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
              <dt class="text-xs text-base-content/40 mb-0.5">Outputs</dt>
              <dd class="text-sm font-mono font-medium">{@details.output_count}</dd>
            </div>
            <%= if Map.has_key?(@details, :weight) do %>
              <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
                <dt class="text-xs text-base-content/40 mb-0.5">Weight</dt>
                <dd class="text-sm font-mono font-medium">
                  {@details.weight} <span class="text-xs text-base-content/35">WU</span>
                </dd>
              </div>
              <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
                <dt class="text-xs text-base-content/40 mb-0.5">vsize</dt>
                <dd class="text-sm font-mono font-medium">
                  {@details.vsize} <span class="text-xs text-base-content/35">vB</span>
                </dd>
              </div>
              <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
                <dt class="text-xs text-base-content/40 mb-0.5">Base size</dt>
                <dd class="text-sm font-mono font-medium">
                  {@details.base_size} <span class="text-xs text-base-content/35">B</span>
                </dd>
              </div>
              <div class="rounded-lg bg-base-300/40 px-3 py-2.5">
                <dt class="text-xs text-base-content/40 mb-0.5">Total size</dt>
                <dd class="text-sm font-mono font-medium">
                  {@details.total_size} <span class="text-xs text-base-content/35">B</span>
                </dd>
              </div>
            <% end %>
          </dl>
        </div>

        <%!-- Inputs table --%>
        <div>
          <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/30 mb-3">
            Inputs
          </h3>
          <div class="overflow-x-auto rounded-lg border border-base-300">
            <table class="w-full text-xs font-mono">
              <thead>
                <tr class="border-b border-base-300 bg-base-300/30 text-base-content/40">
                  <th class="px-3 py-2 text-left font-medium w-8">#</th>
                  <th class="px-3 py-2 text-left font-medium">Prev TxID</th>
                  <th class="px-3 py-2 text-left font-medium">Vout</th>
                  <th class="px-3 py-2 text-left font-medium">Sequence</th>
                  <th class="px-3 py-2 text-left font-medium">Script Sig</th>
                </tr>
              </thead>
              <tbody>
                <%= for {input, i} <- Enum.with_index(@details.inputs) do %>
                  <tr class="border-b border-base-300 last:border-0 hover:bg-base-300/30 transition-colors">
                    <td class="px-3 py-2 text-base-content/30">{i}</td>
                    <td class="px-3 py-2 text-base-content/60">
                      {truncate_hex(input.prev_txid_hex, 16)}
                    </td>
                    <td class="px-3 py-2 text-base-content/60">
                      {if input.prev_vout == 0xFFFFFFFF, do: "coinbase", else: input.prev_vout}
                    </td>
                    <td class="px-3 py-2 text-base-content/50">{input.sequence}</td>
                    <td class="px-3 py-2 text-base-content/50">{input.script_sig_length}B</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Outputs table --%>
        <div>
          <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/30 mb-3">
            Outputs
          </h3>
          <div class="overflow-x-auto rounded-lg border border-base-300">
            <table class="w-full text-xs">
              <thead>
                <tr class="border-b border-base-300 bg-base-300/30 text-base-content/40">
                  <th class="px-3 py-2 text-left font-medium font-mono w-8">#</th>
                  <th class="px-3 py-2 text-left font-medium">Value</th>
                  <th class="px-3 py-2 text-left font-medium">Script Type</th>
                  <th class="px-3 py-2 text-left font-medium font-mono">Script Len</th>
                </tr>
              </thead>
              <tbody>
                <%= for {output, i} <- Enum.with_index(@details.outputs) do %>
                  <tr class="border-b border-base-300 last:border-0 hover:bg-base-300/30 transition-colors">
                    <td class="px-3 py-2 font-mono text-base-content/30">{i}</td>
                    <td class="px-3 py-2">
                      <span class="font-mono text-sm text-base-content/80">
                        {sats_to_btc(output.value_sats)}
                      </span>
                      <span class="font-mono text-xs text-base-content/35 ml-1">BTC</span>
                      <div class="font-mono text-xs text-base-content/30 mt-0.5">
                        {output.value_sats} sat
                      </div>
                    </td>
                    <td class="px-3 py-2">
                      <span class="inline-flex items-center rounded-full bg-base-300 px-2 py-0.5 text-xs font-medium text-base-content/60">
                        {format_script_type(output.script_type)}
                      </span>
                    </td>
                    <td class="px-3 py-2 font-mono text-base-content/50">
                      {output.script_pubkey_length}B
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>

        <%!-- Witnesses section (SegWit only) --%>
        <%= if @details.is_segwit and @details.witnesses != [] do %>
          <div>
            <h3 class="text-xs font-semibold uppercase tracking-wider text-base-content/30 mb-3">
              Witnesses
            </h3>
            <div class="space-y-2">
              <%= for {stack, i} <- Enum.with_index(@details.witnesses) do %>
                <div class="rounded-lg border border-base-300 overflow-hidden">
                  <div class="px-3 py-1.5 bg-base-300/40 text-xs font-mono text-base-content/40 border-b border-base-300">
                    Input {i}
                  </div>
                  <%= if stack == [] do %>
                    <p class="px-3 py-2 text-xs text-base-content/25 italic">empty stack</p>
                  <% else %>
                    <div class="divide-y divide-base-300">
                      <%= for item <- stack do %>
                        <div class="flex items-baseline gap-3 px-3 py-2">
                          <span class="font-mono text-xs text-base-content/25 w-4 shrink-0">
                            {item.index}
                          </span>
                          <span class="font-mono text-xs text-base-content/60 truncate">
                            {truncate_hex(item.item_hex, 40)}
                          </span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp truncate_hex(hex, max) do
    if String.length(hex) > max do
      String.slice(hex, 0, max) <> "…"
    else
      hex
    end
  end

  defp sats_to_btc(sats) do
    whole = div(sats, 100_000_000)
    frac = rem(sats, 100_000_000)
    "#{whole}.#{String.pad_leading(to_string(frac), 8, "0")}"
  end

  defp format_script_type(:p2_p_k_h), do: "P2PKH"
  defp format_script_type(:p2_s_h), do: "P2SH"
  defp format_script_type(:p2_w_p_k_h), do: "P2WPKH"
  defp format_script_type(:p2_w_s_h), do: "P2WSH"
  defp format_script_type(:p2_t_r), do: "P2TR"
  defp format_script_type(:p2_p_k), do: "P2PK"
  defp format_script_type(:multisig), do: "Multisig"
  defp format_script_type(:null_data), do: "OP_RETURN"
  defp format_script_type({:unknown_witness, version: v}), do: "Witness v#{v}"
  defp format_script_type(:non_standard), do: "Non-standard"
  defp format_script_type(other), do: inspect(other)
end
