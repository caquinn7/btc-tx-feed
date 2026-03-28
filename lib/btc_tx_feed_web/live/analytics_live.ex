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
          <p class="text text-base-content mb-2">
            Live aggregate stats from the background sampling pipeline.
          </p>
          <div class="flex items-center gap-4">
            <% failed = Map.get(@stats, :total_failed, 0) %>
            <.link
              navigate={~p"/analytics/failures/decode?session_id=#{@session_id}"}
              class="text-sm text-base-content/50 hover:text-bitcoin transition-colors cursor-pointer"
            >
              {failed} decode {if failed == 1, do: "failure", else: "failures"} &rarr;
            </.link>
            <% consensus_failed = Map.get(@stats, :validation_failure_count, 0) %>
            <.link
              navigate={~p"/analytics/failures/consensus?session_id=#{@session_id}"}
              class="text-sm text-base-content/50 hover:text-bitcoin transition-colors cursor-pointer"
            >
              {consensus_failed} consensus {if consensus_failed == 1,
                do: "violation",
                else: "violations"} &rarr;
            </.link>
            <.link
              navigate={~p"/analytics/history"}
              class="text-sm text-base-content/50 hover:text-bitcoin transition-colors cursor-pointer"
            >
              Session history &rarr;
            </.link>
          </div>
        </div>

        <.stats_pass_rate stats={@stats} />
        <.stats_tx_type stats={@stats} />
        <.stats_vsize stats={@stats} />
        <.stats_script_types stats={@stats} />
        <.stats_version_histogram stats={@stats} />
        <.stats_io_buckets stats={@stats} />

        <.decode_policy_limits policy={@decode_policy} />
      </div>
    </Layouts.app>
    """
  end

  defp decode_policy_assigns, do: BtcTxFeed.DecodePolicy.get()
end
