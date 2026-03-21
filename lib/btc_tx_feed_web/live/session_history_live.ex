defmodule BtcTxFeedWeb.SessionHistoryLive do
  use BtcTxFeedWeb, :live_view

  import BtcTxFeedWeb.StatsComponents

  alias BtcTxFeed.StatsSessions

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    session = StatsSessions.get!(String.to_integer(id))
    {:noreply, assign(socket, :session, session)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :sessions, StatsSessions.list())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/analytics/history"}>
      <%= if @live_action == :index do %>
        <div class="max-w-4xl mx-auto space-y-6">
          <div class="flex items-center justify-between">
            <h1 class="text-xl font-bold">Session History</h1>
            <.link
              navigate={~p"/analytics"}
              class="text-sm text-base-content/50 hover:text-bitcoin transition-colors"
            >
              &larr; Back to live session
            </.link>
          </div>

          <div class="rounded-xl border border-base-300 overflow-hidden">
            <table class="w-full text-sm" id="sessions-table">
              <thead>
                <tr class="border-b border-base-300 bg-base-200">
                  <th class="text-left p-4 text-xs font-semibold uppercase tracking-wider text-base-content/60">
                    Started
                  </th>
                  <th class="text-left p-4 text-xs font-semibold uppercase tracking-wider text-base-content/60">
                    Duration
                  </th>
                  <th class="text-right p-4 text-xs font-semibold uppercase tracking-wider text-base-content/60">
                    Decoded
                  </th>
                  <th class="text-right p-4 text-xs font-semibold uppercase tracking-wider text-base-content/60">
                    Failed
                  </th>
                  <th class="text-right p-4 text-xs font-semibold uppercase tracking-wider text-base-content/60">
                    Pass rate
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@sessions == []}>
                  <td
                    colspan="5"
                    class="p-8 text-center text-sm text-base-content/40"
                  >
                    No sessions recorded yet.
                  </td>
                </tr>
                <%= for session <- @sessions do %>
                  <tr
                    id={"session-row-#{session.id}"}
                    class="border-b last:border-0 border-base-300 hover:bg-base-200/50 cursor-pointer transition-colors"
                    phx-click={JS.navigate(~p"/analytics/history/#{session.id}")}
                  >
                    <td class="p-4 font-mono text-xs">
                      <.link
                        navigate={~p"/analytics/history/#{session.id}"}
                        class="hover:underline"
                      >
                        {format_datetime(session.started_at)}
                      </.link>
                    </td>
                    <td class="p-4 font-mono text-xs text-base-content/60">
                      {format_duration(session.started_at, session.ended_at)}
                    </td>
                    <td class="p-4 text-right font-mono text-xs">{session.total_decoded}</td>
                    <td class="p-4 text-right font-mono text-xs text-base-content/60">
                      {session.total_failed}
                    </td>
                    <td class="p-4 text-right font-mono text-xs">{pass_rate_pct(session)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% else %>
        <div class="max-w-4xl mx-auto space-y-8">
          <%!-- Breadcrumb + metadata --%>
          <div class="flex items-center justify-between">
            <.link
              navigate={~p"/analytics/history"}
              class="text-sm text-base-content/50 hover:text-bitcoin transition-colors"
            >
              &larr; Back to history
            </.link>
            <div class="flex gap-6 text-xs text-base-content/40 font-mono">
              <span>Started: {format_datetime(@session.started_at)}</span>
              <span>Duration: {format_duration(@session.started_at, @session.ended_at)}</span>
            </div>
          </div>

          <.stats_pass_rate stats={@session.counters} />
          <.stats_tx_type stats={@session.counters} />
          <.stats_vsize stats={@session.counters} />
          <.stats_script_types stats={@session.counters} />
          <.stats_version_histogram stats={@session.counters} />
          <.stats_io_buckets stats={@session.counters} />
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp format_duration(_started_at, nil), do: "—"

  defp format_duration(started_at, ended_at) do
    total = DateTime.diff(ended_at, started_at)
    h = div(total, 3600)
    m = div(rem(total, 3600), 60)
    s = rem(total, 60)
    "#{h}h #{m}m #{s}s"
  end

  defp pass_rate_pct(%{total_decoded: decoded, total_failed: failed}) do
    total = decoded + failed
    if total == 0, do: "—", else: "#{Float.round(decoded / total * 100, 1)}%"
  end
end
