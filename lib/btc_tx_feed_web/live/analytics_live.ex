defmodule BtcTxFeedWeb.AnalyticsLive do
  use BtcTxFeedWeb, :live_view

  alias BtcTxFeed.TxStats

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, :refresh)

    {:ok, assign(socket, :stats, TxStats.get())}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :stats, TxStats.get())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/analytics"}>
      <div class="max-w-4xl mx-auto space-y-8">
        <%!-- Page header --%>
        <div>
          <div class="flex items-center justify-between mb-1">
            <h1 class="text-2xl font-bold tracking-tight">Analytics</h1>
            <.link
              navigate={~p"/analytics/failures"}
              class="text-sm text-base-content/50 hover:text-bitcoin transition-colors"
            >
              {failure_count(@stats)} decode {if failure_count(@stats) == 1,
                do: "failure",
                else: "failures"} &rarr;
            </.link>
          </div>
          <p class="text-sm text-base-content/50">
            Live aggregate stats from the background sampling pipeline. Resets on restart.
          </p>
        </div>

        <%!-- Pass rate --%>
        <div class="rounded-xl border border-base-300 bg-base-200 p-5">
          <div class="flex items-baseline justify-between mb-3">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
              Decode pass rate
            </h2>
            <span class="font-mono text-lg font-bold">
              {pass_rate_pct(@stats)}%
            </span>
          </div>
          <div class="h-2.5 rounded-full bg-base-300 overflow-hidden">
            <div
              class="h-full rounded-full bg-green-500 transition-all duration-500"
              style={"width: #{pass_rate_pct(@stats)}%"}
            />
          </div>
          <div class="flex justify-between mt-2 text-xs text-base-content/40 font-mono">
            <span>{Map.get(@stats, :total_decoded, 0)} decoded</span>
            <span>{Map.get(@stats, :total_failed, 0)} failed</span>
          </div>
        </div>

        <%!-- Tx type breakdown --%>
        <div class="rounded-xl border border-base-300 bg-base-200 p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
            Transaction type
          </h2>
          <div class="space-y-2.5">
            <%= for {label, key} <- [{"SegWit", :segwit_count}, {"Legacy", :legacy_count}, {"Coinbase", :coinbase_count}] do %>
              <% count = Map.get(@stats, key, 0) %>
              <% total = Map.get(@stats, :total_decoded, 0) %>
              <div class="flex items-center gap-3">
                <span class="w-20 text-xs text-base-content/60 shrink-0">{label}</span>
                <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                  <div
                    class="h-full rounded-full bg-orange-400 transition-all duration-500"
                    style={"width: #{pct(count, total)}%"}
                  />
                </div>
                <span class="w-16 text-right font-mono text-xs text-base-content/50">
                  {count}
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- vsize buckets --%>
        <div class="rounded-xl border border-base-300 bg-base-200 p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
            Virtual size distribution
          </h2>
          <div class="space-y-2.5">
            <%= for {label, bucket} <- [
              {"Tiny (<250)", :tiny},
              {"Small (250–500)", :small},
              {"Medium (500–1k)", :medium},
              {"Large (1k–5k)", :large},
              {"Oversized (>5k)", :oversized}
            ] do %>
              <% count = Map.get(@stats, {:vsize_bucket, bucket}, 0) %>
              <% total = vsize_total(@stats) %>
              <div class="flex items-center gap-3">
                <span class="w-36 text-xs text-base-content/60 shrink-0">{label}</span>
                <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                  <div
                    class="h-full rounded-full bg-blue-400 transition-all duration-500"
                    style={"width: #{pct(count, total)}%"}
                  />
                </div>
                <span class="w-16 text-right font-mono text-xs text-base-content/50">
                  {count}
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Script type distribution --%>
        <div class="rounded-xl border border-base-300 bg-base-200 p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
            Output script types
          </h2>
          <div class="space-y-2.5">
            <%= for {label, type} <- script_type_rows(@stats) do %>
              <% count = Map.get(@stats, {:script_type, type}, 0) %>
              <% total = script_type_total(@stats) %>
              <div class="flex items-center gap-3">
                <span class="w-32 text-xs text-base-content/60 shrink-0">{label}</span>
                <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                  <div
                    class="h-full rounded-full bg-violet-400 transition-all duration-500"
                    style={"width: #{pct(count, total)}%"}
                  />
                </div>
                <span class="w-16 text-right font-mono text-xs text-base-content/50">
                  {count}
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Version histogram --%>
        <div class="rounded-xl border border-base-300 bg-base-200 p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
            Version histogram
          </h2>
          <div class="space-y-2.5">
            <%= for {v, count} <- version_rows(@stats) do %>
              <% total = Map.get(@stats, :total_decoded, 0) %>
              <div class="flex items-center gap-3">
                <span class="w-16 text-xs text-base-content/60 shrink-0 font-mono">v{v}</span>
                <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                  <div
                    class="h-full rounded-full bg-amber-400 transition-all duration-500"
                    style={"width: #{pct(count, total)}%"}
                  />
                </div>
                <span class="w-16 text-right font-mono text-xs text-base-content/50">
                  {count}
                </span>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Input / output count buckets --%>
        <div class="grid grid-cols-2 gap-6">
          <div class="rounded-xl border border-base-300 bg-base-200 p-5">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
              Input count
            </h2>
            <div class="space-y-2.5">
              <%= for {label, bucket} <- [{"Single", :single}, {"Few (2–5)", :few}, {"Many (>5)", :many}] do %>
                <% count = Map.get(@stats, {:input_bucket, bucket}, 0) %>
                <% total = bucket_total(@stats, :input_bucket) %>
                <div class="flex items-center gap-3">
                  <span class="w-20 text-xs text-base-content/60 shrink-0">{label}</span>
                  <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                    <div
                      class="h-full rounded-full bg-cyan-400 transition-all duration-500"
                      style={"width: #{pct(count, total)}%"}
                    />
                  </div>
                  <span class="w-10 text-right font-mono text-xs text-base-content/50">
                    {count}
                  </span>
                </div>
              <% end %>
            </div>
          </div>

          <div class="rounded-xl border border-base-300 bg-base-200 p-5">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
              Output count
            </h2>
            <div class="space-y-2.5">
              <%= for {label, bucket} <- [{"Single", :single}, {"Few (2–5)", :few}, {"Many (>5)", :many}] do %>
                <% count = Map.get(@stats, {:output_bucket, bucket}, 0) %>
                <% total = bucket_total(@stats, :output_bucket) %>
                <div class="flex items-center gap-3">
                  <span class="w-20 text-xs text-base-content/60 shrink-0">{label}</span>
                  <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                    <div
                      class="h-full rounded-full bg-teal-400 transition-all duration-500"
                      style={"width: #{pct(count, total)}%"}
                    />
                  </div>
                  <span class="w-10 text-right font-mono text-xs text-base-content/50">
                    {count}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp pass_rate_pct(stats) do
    decoded = Map.get(stats, :total_decoded, 0)
    failed = Map.get(stats, :total_failed, 0)
    total = decoded + failed
    if total == 0, do: 0, else: Float.round(decoded / total * 100, 1)
  end

  defp failure_count(stats), do: Map.get(stats, :total_failed, 0)

  defp pct(_count, 0), do: 0
  defp pct(count, total), do: Float.round(count / total * 100, 1)

  defp vsize_total(stats) do
    [:tiny, :small, :medium, :large, :oversized]
    |> Enum.sum_by(&Map.get(stats, {:vsize_bucket, &1}, 0))
  end

  defp script_type_total(stats) do
    stats
    |> Enum.filter(fn {k, _} -> match?({:script_type, _}, k) end)
    |> Enum.sum_by(fn {_, v} -> v end)
  end

  defp script_type_rows(stats) do
    known = [
      {"P2TR", :p2_t_r},
      {"P2WPKH", :p2_w_p_k_h},
      {"P2WSH", :p2_w_s_h},
      {"P2PKH", :p2_p_k_h},
      {"P2SH", :p2_s_h},
      {"P2PK", :p2_p_k},
      {"Multisig", :multisig},
      {"OP_RETURN", :null_data},
      {"Non-standard", :non_standard}
    ]

    seen_types = for {{:script_type, t}, _} <- stats, into: MapSet.new(), do: t
    known_types = for {_, t} <- known, into: MapSet.new(), do: t
    unknown_extra = MapSet.difference(seen_types, known_types)

    known ++
      Enum.map(unknown_extra, fn t -> {"Unknown (#{inspect(t)})", t} end)
  end

  defp version_rows(stats) do
    stats
    |> Enum.filter(fn {k, _} -> match?({:version, _}, k) end)
    |> Enum.map(fn {{:version, v}, count} -> {v, count} end)
    |> Enum.sort_by(fn {v, _} -> v end)
  end

  defp bucket_total(stats, prefix) do
    [:single, :few, :many]
    |> Enum.sum_by(&Map.get(stats, {prefix, &1}, 0))
  end
end
