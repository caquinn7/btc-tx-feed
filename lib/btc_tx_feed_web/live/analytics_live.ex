defmodule BtcTxFeedWeb.AnalyticsLive do
  use BtcTxFeedWeb, :live_view

  import BtcTxFeedWeb.StatsComponents
  alias BtcTxFeed.TxStats

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, :refresh)

    {:ok,
     socket
     |> assign(:stats, TxStats.get())
     |> assign(:session_id, TxStats.get_session_id())
     |> assign(:decode_policy, decode_policy_assigns())}
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
            <p class="text text-base-content">
              Live aggregate stats from the background sampling pipeline.
            </p>
            <div class="flex items-center gap-4">
              <% failed = Map.get(@stats, :total_failed, 0) %>
              <.link
                navigate={~p"/analytics/failures?session_id=#{@session_id}"}
                class="text-sm text-base-content/50 hover:text-bitcoin transition-colors"
              >
                {failed} decode {if failed == 1, do: "failure", else: "failures"} &rarr;
              </.link>
              <.link
                navigate={~p"/analytics/history"}
                class="text-sm text-base-content/50 hover:text-bitcoin transition-colors"
              >
                Session history &rarr;
              </.link>
            </div>
          </div>
        </div>

        <.stats_pass_rate stats={@stats} />
        <.stats_tx_type stats={@stats} />
        <.stats_vsize stats={@stats} />
        <.stats_script_types stats={@stats} />
        <.stats_version_histogram stats={@stats} />
        <.stats_io_buckets stats={@stats} />

        <%!-- Decode policy --%>
        <div class="rounded-xl border border-base-300 bg-base-200 p-5">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60 mb-4">
            Decode policy limits
          </h2>
          <div class="grid grid-cols-2 gap-x-8 gap-y-2">
            <%= for {label, value, unit} <- [
              {"Max tx size", @decode_policy.max_tx_size, :bytes},
              {"Max inputs", @decode_policy.max_vin_count, :count},
              {"Max outputs", @decode_policy.max_vout_count, :count},
              {"Max script size", @decode_policy.max_script_size, :bytes},
              {"Max witness items / input", @decode_policy.max_witness_items_per_input, :count},
              {"Max witness size / input", @decode_policy.max_witness_size_per_input, :bytes}
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
      </div>
    </Layouts.app>
    """
  end

  defp decode_policy_assigns, do: BtcTxFeed.DecodePolicy.get()
end
