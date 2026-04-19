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
      |> assign(:hex_form, to_form(%{"hex" => ""}, as: :hex_form))
      |> assign(:txid_dirty, false)
      |> assign(:hex_dirty, false)
      |> assign(:decoded_hex, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"txid" => txid}, _uri, socket) do
    txid = String.trim(txid)

    socket =
      if socket.assigns.searched_txid == txid and
           match?({:ok, _, _}, socket.assigns.tx_details) do
        socket
        |> assign(:form, to_form(%{"txid" => txid}, as: :lookup))
        |> assign(:txid_dirty, false)
      else
        socket
        |> assign(:form, to_form(%{"txid" => txid}, as: :lookup))
        |> assign(:txid_dirty, false)
        |> start_fetch(txid)
      end

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
      |> assign(:txid_dirty, false)
      |> assign(:hex_dirty, false)
      |> assign(:decoded_hex, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, result}, socket) when ref == socket.assigns.task_ref do
    Process.demonitor(ref, [:flush])

    {decoded_hex, form_hex} =
      case result do
        {:ok, _details, raw_hex} -> {raw_hex, raw_hex}
        _ -> {nil, ""}
      end

    socket =
      socket
      |> assign(:tx_details, result)
      |> assign(:task_ref, nil)
      |> assign(:txid_dirty, false)
      |> assign(:hex_dirty, false)
      |> assign(:decoded_hex, decoded_hex)
      |> assign(:hex_form, to_form(%{"hex" => form_hex}, as: :hex_form))

    {:noreply, socket}
  end

  # Stale result from a previous task whose ref was replaced — discard it.
  def handle_info({_ref, _result}, socket) do
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

  @impl true
  def handle_event("decode_hex", %{"hex_form" => %{"hex" => hex}}, socket) do
    if socket.assigns.task_ref do
      Process.demonitor(socket.assigns.task_ref, [:flush])
    end

    hex =
      hex
      |> String.trim()
      |> String.downcase()

    result =
      case TxParser.parse_hex(hex) do
        {:ok, details} -> {:ok, details, hex}
        err -> err
      end

    txid =
      case result do
        {:ok, details, _} -> details.txid
        _ -> nil
      end

    socket =
      socket
      |> assign(:task_ref, nil)
      |> assign(:tx_details, result)
      |> assign(:searched_txid, txid)
      |> assign(:txid_dirty, false)
      |> assign(:hex_dirty, false)
      |> assign(:decoded_hex, if(txid, do: hex, else: nil))
      |> assign(:form, to_form(%{"txid" => txid || ""}, as: :lookup))

    socket =
      if txid do
        push_patch(socket, to: ~p"/tx/#{txid}")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_lookup", %{"lookup" => %{"txid" => txid}}, socket) do
    dirty =
      socket.assigns.searched_txid != nil and
        String.trim(txid) != socket.assigns.searched_txid

    {:noreply, assign(socket, :txid_dirty, dirty)}
  end

  @impl true
  def handle_event("validate_hex", %{"hex_form" => %{"hex" => hex}}, socket) do
    dirty =
      socket.assigns.decoded_hex != nil and
        String.trim(hex) != socket.assigns.decoded_hex

    {:noreply, assign(socket, :hex_dirty, dirty)}
  end

  defp start_fetch(socket, txid) do
    if socket.assigns.task_ref do
      Process.demonitor(socket.assigns.task_ref, [:flush])
    end

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
        <.form
          for={@form}
          id="tx-lookup-form"
          phx-submit="lookup"
          phx-change="validate_lookup"
          class="mb-3"
        >
          <div class="flex gap-3 items-center">
            <input
              id={@form[:txid].id}
              name={@form[:txid].name}
              type="text"
              value={@form[:txid].value}
              spellcheck="false"
              placeholder="Paste a txid to fetch and decode the raw transaction…"
              class={[
                "flex-1 h-12 rounded-xl border px-4 font-mono text-xs text-base-content placeholder:text-base-content/30 focus:outline-none bg-base-200",
                if(@txid_dirty,
                  do: "border-amber-400/60",
                  else: "border-base-300 focus:border-base-content/20"
                )
              ]}
            />
            <button
              type="submit"
              class="w-36 h-12 rounded-xl bg-blue-500/15 text-blue-400 border border-blue-500/30 font-semibold hover:opacity-80 transition-opacity shrink-0 cursor-pointer"
            >
              Decode
            </button>
          </div>
        </.form>

        <.form
          for={@hex_form}
          id="hex-decode-form"
          phx-submit="decode_hex"
          phx-change="validate_hex"
          class="mb-8"
        >
          <div class="flex gap-3 items-start">
            <textarea
              id="hex-decode-input"
              name={@hex_form[:hex].name}
              rows="6"
              placeholder="Or paste raw transaction hex…"
              spellcheck="false"
              class={[
                "flex-1 rounded-xl border px-4 py-3 font-mono text-xs leading-relaxed text-base-content placeholder:text-base-content/30 focus:outline-none bg-base-200",
                if(@hex_dirty,
                  do: "border-amber-400/60",
                  else: "border-base-300 focus:border-base-content/20"
                )
              ]}
            >{Phoenix.HTML.Form.normalize_value("textarea", @hex_form[:hex].value)}</textarea>
            <button
              type="submit"
              class="w-36 h-12 rounded-xl bg-bitcoin/15 text-bitcoin border border-bitcoin/30 font-semibold hover:opacity-80 transition-opacity shrink-0 cursor-pointer mt-1"
            >
              Decode Hex
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
