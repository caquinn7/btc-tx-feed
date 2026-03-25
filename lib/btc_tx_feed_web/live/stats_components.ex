defmodule BtcTxFeedWeb.StatsComponents do
  use BtcTxFeedWeb, :html

  attr :stats, :map, required: true

  def stats_pass_rate(assigns) do
    ~H"""
    <div id="stats-pass-rate" class="rounded-xl border border-base-300 bg-base-200 p-5">
      <div class="flex items-baseline justify-between mb-3">
        <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
          Decode pass rate
        </h2>
        <span class="font-mono text-lg font-bold">
          {pass_rate_percentage(@stats)}%
        </span>
      </div>
      <div class="h-2.5 rounded-full bg-base-300 overflow-hidden">
        <div
          class="h-full rounded-full bg-green-500 transition-all duration-500"
          style={"width: #{pass_rate_percentage(@stats)}%"}
        />
      </div>
      <div class="flex justify-between mt-2 text-xs text-base-content/40 font-mono">
        <span>{Map.get(@stats, :total_decoded, 0)} decoded</span>
        <span>{Map.get(@stats, :total_failed, 0)} failed</span>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true

  def stats_tx_type(assigns) do
    ~H"""
    <div id="stats-tx-type" class="rounded-xl border border-base-300 bg-base-200 p-5">
      <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
        Transaction type
      </h2>
      <div class="space-y-2.5">
        <% tx_type_max = tx_type_max(@stats) %>
        <%= for {label, key} <- [{"SegWit", :segwit_count}, {"Legacy", :legacy_count}, {"Coinbase", :coinbase_count}] do %>
          <% count = Map.get(@stats, key, 0) %>
          <div class="flex items-center gap-3">
            <span class="w-20 text-xs text-base-content/60 shrink-0">{label}</span>
            <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
              <div
                class="h-full rounded-full bg-orange-400 transition-all duration-500"
                style={"width: #{bar_width(count, tx_type_max)}%"}
              />
            </div>
            <span class="w-16 text-right font-mono text-xs text-base-content/50">
              {count}
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true

  def stats_vsize(assigns) do
    ~H"""
    <div id="stats-vsize" class="rounded-xl border border-base-300 bg-base-200 p-5">
      <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
        Virtual size distribution
      </h2>
      <div class="space-y-2.5">
        <% vsize_max = vsize_max(@stats) %>
        <%= for {label, bucket} <- [
          {"Tiny (< 250)", :tiny},
          {"Small (250 - 500)", :small},
          {"Medium (500 - 1k)", :medium},
          {"Large (1k - 5k)", :large},
          {"Oversized (> 5k)", :oversized}
        ] do %>
          <% count = Map.get(@stats, {:vsize_bucket, bucket}, 0) %>
          <div class="flex items-center gap-3">
            <span class="w-36 text-xs text-base-content/60 shrink-0">{label}</span>
            <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
              <div
                class="h-full rounded-full bg-blue-400 transition-all duration-500"
                style={"width: #{bar_width(count, vsize_max)}%"}
              />
            </div>
            <span class="w-16 text-right font-mono text-xs text-base-content/50">
              {count}
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true

  def stats_script_types(assigns) do
    ~H"""
    <div id="stats-script-types" class="rounded-xl border border-base-300 bg-base-200 p-5">
      <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
        Output script types
      </h2>
      <div class="space-y-2.5">
        <% script_max = script_type_max(@stats) %>
        <%= for {label, type} <- script_type_rows(@stats) do %>
          <% count = Map.get(@stats, {:script_type, type}, 0) %>
          <div class="flex items-center gap-3">
            <span class="w-32 text-xs text-base-content/60 shrink-0">{label}</span>
            <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
              <div
                class="h-full rounded-full bg-violet-400 transition-all duration-500"
                style={"width: #{bar_width(count, script_max)}%"}
              />
            </div>
            <span class="w-16 text-right font-mono text-xs text-base-content/50">
              {count}
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true

  def stats_version_histogram(assigns) do
    ~H"""
    <div id="stats-version-histogram" class="rounded-xl border border-base-300 bg-base-200 p-5">
      <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
        Version histogram
      </h2>
      <div class="space-y-2.5">
        <% version_max = version_max(@stats) %>
        <%= for {v, count} <- version_rows(@stats) do %>
          <div class="flex items-center gap-3">
            <span class="w-16 text-xs text-base-content/60 shrink-0 font-mono">v{v}</span>
            <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
              <div
                class="h-full rounded-full bg-amber-400 transition-all duration-500"
                style={"width: #{bar_width(count, version_max)}%"}
              />
            </div>
            <span class="w-16 text-right font-mono text-xs text-base-content/50">
              {count}
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true

  def stats_io_buckets(assigns) do
    ~H"""
    <div id="stats-io-buckets" class="grid grid-cols-2 gap-6">
      <div class="rounded-xl border border-base-300 bg-base-200 p-5">
        <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
          Input count
        </h2>
        <div class="space-y-2.5">
          <% input_max = bucket_max(@stats, :input_bucket) %>
          <%= for {label, bucket} <- [{"Single", :single}, {"Few (2 - 5)", :few}, {"Many (> 5)", :many}] do %>
            <% count = Map.get(@stats, {:input_bucket, bucket}, 0) %>
            <div class="flex items-center gap-3">
              <span class="w-20 text-xs text-base-content/60 shrink-0">{label}</span>
              <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                <div
                  class="h-full rounded-full bg-cyan-400 transition-all duration-500"
                  style={"width: #{bar_width(count, input_max)}%"}
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
          <% output_max = bucket_max(@stats, :output_bucket) %>
          <%= for {label, bucket} <- [{"Single", :single}, {"Few (2 - 5)", :few}, {"Many (> 5)", :many}] do %>
            <% count = Map.get(@stats, {:output_bucket, bucket}, 0) %>
            <div class="flex items-center gap-3">
              <span class="w-20 text-xs text-base-content/60 shrink-0">{label}</span>
              <div class="flex-1 h-2 rounded-full bg-base-300 overflow-hidden">
                <div
                  class="h-full rounded-full bg-teal-400 transition-all duration-500"
                  style={"width: #{bar_width(count, output_max)}%"}
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
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp pass_rate_percentage(stats) do
    decoded = Map.get(stats, :total_decoded, 0)
    failed = Map.get(stats, :total_failed, 0)
    total = decoded + failed
    value = if total == 0, do: 0.0, else: Float.floor(decoded / total * 100, 2)
    :erlang.float_to_binary(value * 1.0, decimals: 2)
  end

  defp bar_width(_count, 0), do: 0
  defp bar_width(0, _max), do: 0

  defp bar_width(count, max) do
    width = Float.round(count / max * 100, 1)
    max(width, 0.5)
  end

  defp tx_type_max(stats) do
    [:segwit_count, :legacy_count, :coinbase_count]
    |> Enum.map(&Map.get(stats, &1, 0))
    |> Enum.max(fn -> 0 end)
  end

  defp vsize_max(stats) do
    [:tiny, :small, :medium, :large, :oversized]
    |> Enum.map(&Map.get(stats, {:vsize_bucket, &1}, 0))
    |> Enum.max(fn -> 0 end)
  end

  defp script_type_max(stats) do
    stats
    |> Enum.filter(fn {k, _} -> match?({:script_type, _}, k) end)
    |> Enum.map(fn {_, v} -> v end)
    |> Enum.max(fn -> 0 end)
  end

  defp bucket_max(stats, prefix) do
    [:single, :few, :many]
    |> Enum.map(&Map.get(stats, {prefix, &1}, 0))
    |> Enum.max(fn -> 0 end)
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

  defp version_max(stats) do
    stats
    |> Enum.filter(fn {k, _} -> match?({:version, _}, k) end)
    |> Enum.map(fn {_, count} -> count end)
    |> Enum.max(fn -> 0 end)
  end

  attr :policy, :map, required: true

  def decode_policy_limits(assigns) do
    ~H"""
    <div id="stats-decode-policy" class="rounded-xl border border-base-300 bg-base-200 p-5">
      <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
        Decode policy limits
      </h2>
      <div class="grid grid-cols-2 gap-x-8 gap-y-2">
        <%= for {label, value, unit} <- [
          {"Max tx size", @policy.max_tx_size, :bytes},
          {"Max inputs", @policy.max_vin_count, :count},
          {"Max outputs", @policy.max_vout_count, :count},
          {"Max script size", @policy.max_script_size, :bytes},
          {"Max witness items / input", @policy.max_witness_items_per_input, :count},
          {"Max witness size / input", @policy.max_witness_size_per_input, :bytes}
        ] do %>
          <div class="flex items-baseline justify-between py-1.5 border-b border-base-300">
            <span class="text-xs text-base-content/60">{label}</span>
            <span class="font-mono text-xs text-base-content/80">
              {value}
              <%= if unit == :bytes do %>
                <span class="text-base-content/35">B</span>
              <% end %>
            </span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
