defmodule BtcTxFeedWeb.DecodeFailuresLive do
  use BtcTxFeedWeb, :live_view

  alias BtcTxFeed.{FailureStore, StatsSessions}

  @impl true
  def mount(params, _session, socket) do
    case parse_session_id(params["session_id"]) do
      {:ok, session_id} ->
        session = StatsSessions.get!(session_id)
        failures = FailureStore.list_decode_failures_for_session(session_id)

        back_path =
          if session.ended_at, do: ~p"/analytics/history/#{session_id}", else: ~p"/analytics"

        socket =
          socket
          |> assign(:back_path, back_path)
          |> assign(:scoped?, true)
          |> stream(:failures, failures)

        {:ok, socket}

      :no_param ->
        failures = FailureStore.list_decode_failures_recent(50)

        socket =
          socket
          |> assign(:back_path, ~p"/analytics")
          |> assign(:scoped?, false)
          |> stream(:failures, failures)

        {:ok, socket}

      :invalid ->
        {:ok, push_navigate(socket, to: ~p"/analytics")}
    end
  end

  defp parse_session_id(nil), do: :no_param

  defp parse_session_id(raw) do
    case Integer.parse(raw) do
      {id, ""} -> {:ok, id}
      _ -> :invalid
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/analytics/failures/decode"}>
      <div class="max-w-4xl mx-auto">
        <%!-- Page header --%>
        <div class="mb-8">
          <div class="flex items-center justify-between mb-1">
            <h1 class="text-2xl font-bold tracking-tight">Decode Failures</h1>
            <.link
              navigate={@back_path}
              class="text-sm text-base-content/50 hover:text-bitcoin transition-colors cursor-pointer"
            >
              &larr; Back to live session
            </.link>
          </div>
          <p class="text-sm text-base-content/50">
            <%= if @scoped? do %>
              Transactions that failed to decode in this session.
            <% else %>
              Last 50 transactions that failed to decode.
            <% end %>
          </p>
        </div>

        <%!-- Table --%>
        <div class="rounded-xl border border-base-300 overflow-hidden">
          <div id="failures" phx-update="stream">
            <%!-- Empty state --%>
            <div
              id="failures-empty-state"
              class="hidden only:block text-center text-sm text-base-content/40 py-16"
            >
              No decode failures recorded yet.
            </div>

            <div
              :for={{id, failure} <- @streams.failures}
              id={id}
              class="border-b border-base-300 last:border-0 p-5"
            >
              <div class="flex items-start justify-between gap-4 mb-2">
                <div class="space-y-1 min-w-0">
                  <%!-- txid --%>
                  <p class="font-mono text-sm text-base-content/80 break-all">
                    <%= if failure.txid do %>
                      {failure.txid}
                    <% else %>
                      <span class="text-base-content/30 italic">txid unavailable</span>
                    <% end %>
                  </p>
                  <%!-- Error reason --%>
                  <p class="text-xs text-red-400/80 font-mono break-all">
                    {failure.error_reason}
                  </p>
                </div>
                <%!-- Timestamp --%>
                <time
                  class="text-xs text-base-content/40 font-mono shrink-0 mt-0.5"
                  datetime={NaiveDateTime.to_iso8601(failure.inserted_at)}
                >
                  {Calendar.strftime(failure.inserted_at, "%Y-%m-%d %H:%M:%S")} UTC
                </time>
              </div>

              <%!-- Raw hex (expandable) --%>
              <details class="mt-2">
                <summary class="text-xs text-base-content/40 cursor-pointer hover:text-base-content/60 transition-colors select-none">
                  Raw hex
                </summary>
                <pre class="mt-2 p-3 rounded-lg bg-base-300 text-xs font-mono text-base-content/60 break-all overflow-x-auto whitespace-pre-wrap">{failure.raw_hex}</pre>
              </details>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
