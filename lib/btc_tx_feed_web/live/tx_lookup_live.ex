defmodule BtcTxFeedWeb.TxLookupLive do
  use BtcTxFeedWeb, :live_view

  import BtcTxFeedWeb.TxComponents

  alias BtcTxFeed.{MempoolHttpClient, TxParser}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:tx_details, nil)
      |> assign(:searched_txid, nil)
      |> assign(:task_ref, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"txid" => txid}, _uri, socket) do
    txid = String.trim(txid)

    socket =
      socket
      |> assign(:form, to_form(%{"txid" => txid}, as: :lookup))
      |> start_fetch(txid)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    if socket.assigns.task_ref do
      Process.demonitor(socket.assigns.task_ref, [:flush])
    end

    socket =
      socket
      |> assign(:form, to_form(%{"txid" => ""}, as: :lookup))
      |> assign(:tx_details, nil)
      |> assign(:searched_txid, nil)
      |> assign(:task_ref, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, result}, socket) when ref == socket.assigns.task_ref do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(:tx_details, result)
      |> assign(:task_ref, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("lookup", %{"lookup" => %{"txid" => txid}}, socket) do
    txid = String.trim(txid)
    {:noreply, push_patch(socket, to: ~p"/tx/#{txid}")}
  end

  defp start_fetch(socket, txid) do
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

    socket
    |> assign(:searched_txid, txid)
    |> assign(:tx_details, :loading)
    |> assign(:task_ref, task.ref)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path={~p"/tx"}>
      <div class="max-w-4xl mx-auto">
        <div class="mb-2">
          <p class="text text-base-content">
            Paste a txid to fetch and decode the raw transaction.
          </p>
        </div>

        <.form for={@form} id="tx-lookup-form" phx-submit="lookup" class="mb-8">
          <div class="flex gap-3 items-center">
            <div class="flex-1 [&_.fieldset]:mb-0">
              <.input
                field={@form[:txid]}
                type="text"
                class="w-full input h-12 focus:outline-none"
                spellcheck="false"
              />
            </div>
            <button
              type="submit"
              class="h-12 px-5 rounded-xl bg-bitcoin text-white font-semibold hover:opacity-90 transition-opacity shrink-0 cursor-pointer"
            >
              Decode
            </button>
          </div>
        </.form>

        <%= cond do %>
          <% @tx_details == nil -> %>
          <% @tx_details == :loading -> %>
            <div id="tx-lookup-loading" class="rounded-xl border border-base-300 bg-base-200 p-6">
              <div class="flex items-center gap-3 mb-4">
                <div class="size-4 rounded-full border-2 border-orange-400/30 border-t-orange-400 animate-spin shrink-0" />
                <span class="text-sm text-base-content/60">Decoding transaction…</span>
              </div>
              <p class="font-mono text-xs text-base-content/40 break-all mb-6">
                {@searched_txid}
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
            <div id="tx-lookup-error" class="rounded-xl border border-red-500/20 bg-red-500/5 p-6">
              <div class="flex items-center gap-3 mb-3">
                <.icon name="hero-exclamation-triangle" class="size-5 text-red-400 shrink-0" />
                <span class="text-sm font-semibold text-red-400">Failed to load transaction</span>
              </div>
              <p class="font-mono text-xs text-base-content/40 break-all mb-3">
                txid {@searched_txid}
              </p>
              <p class="font-mono text-xs text-base-content/50 break-all">
                {inspect(elem(@tx_details, 1))}
              </p>
            </div>
          <% true -> %>
            <.tx_details_card details={elem(@tx_details, 1)} raw_hex={elem(@tx_details, 2)} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
