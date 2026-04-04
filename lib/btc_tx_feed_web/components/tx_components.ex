defmodule BtcTxFeedWeb.TxComponents do
  use BtcTxFeedWeb, :html

  attr :details, :map, required: true

  def tx_details_card(assigns) do
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
