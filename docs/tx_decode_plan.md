# Plan: TX Decode on Click + Details Panel

## TL;DR

When the user clicks a txid, the LiveView fires a `Task.async` to fetch raw bytes
and decode them via the `btc_tx` library. All extracted data populates a new
right-hand details column alongside the existing txid list.

---

## Phase 1 – Data extraction module

1. Create `lib/btc_tx_feed/tx_parser.ex` — `BtcTxFeed.TxParser.parse(raw_bytes)`
   returning `{:ok, details_map} | {:error, reason}`.
   - Call `:btc_tx.decode(raw_bytes)` → decode error propagates
   - Attempt `:btc_tx.validate_consensus(tx)` — validated tx used for txid/wtxid/weight/vsize;
     unvalidated tx covers inputs/outputs/witnesses regardless
   - Extract overview: version, `is_segwit`, `lock_time`, `has_coinbase_marker`, input/output counts
   - If validated: txid + wtxid as BE hex, `base_size`, `total_size`, `weight`, `vsize`
   - Extract inputs list: `%{prev_txid_hex, prev_vout, sequence, script_sig_hex, script_sig_length}`
   - Extract outputs list: `%{value_sats, script_type, script_pubkey_hex, script_pubkey_length}`
   - Extract witnesses if segwit: list of stacks, each a list of `%{index, item_hex}`
   - Private BE-hex helper: reverse binary → `Base.encode16(case: :lower)`

---

## Phase 2 – LiveView async wiring

2. Add assigns in `mount/3`: `selected_txid: nil`, `tx_details: nil`, `task_ref: nil`
3. Update `handle_event("clicked_txid", ...)`:
   - Assign `selected_txid` and `tx_details: :loading`
   - Spawn `Task.async(fn -> MempoolHttpClient.get_raw_tx(txid) |> parse_if_ok end)`
   - Store `task.ref` in `task_ref`
4. Add `handle_info({ref, result}, socket)` guarded by `ref == socket.assigns.task_ref`:
   - `Process.demonitor(ref, [:flush])`
   - Assign `tx_details: {:ok, map} | {:error, reason}`
   - Clear `task_ref`
5. Add catch-all `handle_info({:DOWN, ...})` → `{:noreply, socket}`

---

## Phase 3 – Two-column UI

6. Restructure template with a top-level `flex` container:
   - **Left column** (`w-2/5 shrink-0`): existing page header + stats bar + txid stream list;
     highlight the selected row
   - **Right column** (`flex-1 min-w-0`): transaction details panel

7. Details panel states:
   - `nil` → "Select a transaction to inspect it" empty state with icon
   - `:loading` → skeleton/spinner with selected txid shown
   - `{:error, reason}` → error card
   - `{:ok, details}` → full details card

8. Details card layout:
   - **Header**: full txid (monospace), SegWit badge, Coinbase badge if applicable
   - **Overview grid**: Version, Lock Time, Inputs, Outputs, Weight, vsize, base/total size
     (weight/size rows only present when validated)
   - **Inputs section**: table — prev txid (truncated), vout, sequence, script sig length
   - **Outputs section**: table — value in BTC + sats, script type badge, script length
   - **Witnesses section** (SegWit only): per-input stacks, items as truncated hex

---

## Relevant Files

| File | Role |
|---|---|
| `lib/btc_tx_feed/tx_parser.ex` | New module — create |
| `lib/btc_tx_feed_web/live/mempool_live.ex` | All LiveView changes |
| `docs/btc_tx_api.md` | btc_tx call reference |
| `lib/btc_tx_feed/mempool_http_client.ex` | No changes needed |

---

## Verification

1. `mix compile --warnings-as-errors` passes
2. Clicking a txid shows loading state → decoded details populate in right column
3. SegWit tx shows witnesses section; legacy tx does not
4. Coinbase tx shows coinbase badge
5. Network/decode error shows error state gracefully
6. Clicking a second txid while the first is loading replaces with the new task result
7. `mix precommit` passes clean

---

## Decisions

- `Task.async` directly in the LiveView — no supervisor needed; HTTP errors are
  caught and returned, task cannot crash the LiveView
- No LiveComponent for the details panel — inline per project guidelines
- `validate_consensus` is attempted but failure does not block display of raw decoded
  data; weight/txid fields are simply omitted when validation fails
- Long hex values (script bytes, witness items) truncated to ~40 chars in the UI

---

## Notes

- Clicking a new txid while a task is in-flight is safe: the old task ref is
  orphaned and its eventual `handle_info` won't match the new `task_ref`; the
  `:DOWN` message is caught by the catch-all clause.
- Script sig classification is not attempted for inputs — `classify_output_script`
  is output-only. Raw hex + length is shown for inputs.
