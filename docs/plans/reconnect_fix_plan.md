# Plan: Fix WebSocket Reconnection After Sleep

**TL;DR:** Three separate bugs compound to cause the broken state. The critical one is that `send(self(), :connect)` is never handled, so the GenServer stays permanently stuck. Fix that first, then add a keepalive ping so stale connections are detected before the failure, and update the LiveView's "Live" badge to reflect actual upstream socket status.

---

## Steps

### Phase 1 — Fix the broken `:connect` handler (critical bug)

1. Add `handle_info(:connect, state)` clause **before** the catch-all in `lib/btc_tx_feed/mempool_socket.ex`. It should close any existing connection gracefully and return `{:noreply, %__MODULE__{retry_count: state.retry_count}, {:continue, :connect}}` — reusing the existing `handle_continue(:connect)` logic.

2. Add `retry_count: 0` to the struct's default fields so the new clause can thread it through.

### Phase 2 — Exponential backoff instead of immediate retry

3. Change the `else` clause in `handle_continue(:connect, state)` — which currently calls `{:stop, reason, state}` — to instead schedule a retry via `Process.send_after(self(), :connect, backoff_delay(state.retry_count))` and return `{:noreply, %__MODULE__{retry_count: state.retry_count + 1}}`. This also prevents the supervisor's default 3-restarts-in-5-seconds limit from killing the process permanently if mempool.space is temporarily unreachable.

4. Add a private `backoff_delay(retry_count)` function that returns `min(1_000 * 2^retry_count, 30_000)` plus ±20% random jitter via `:rand.uniform/1`.

5. Reset `retry_count` to `0` in the `handle_response` clause for `{:done, ref}` (WebSocket upgrade success), also broadcast `{:socket_status, :connected}` to a new PubSub topic `"mempool:status"` here.

6. Broadcast `{:socket_status, :disconnected}` in the error/close paths (stream error catch, close frame handler) before scheduling `:connect`.

### Phase 3 — Keepalive ping to detect stale post-sleep connections

7. Add `ping_timer: nil` to the struct.

8. In `handle_response` for `{:done, ref}`, after broadcasting `:connected`, schedule the first keepalive: `Process.send_after(self(), :keepalive, 30_000)` and store the ref in `state.ping_timer`.

9. Add `handle_info(:keepalive, state)` that calls `send_frame(state, {:ping, ""})`. On success, reschedule another `:keepalive` in 30s. On failure, cancel the timer, broadcast `:disconnected`, and trigger the `:connect` path. This means when your computer wakes up, the first attempted ping will fail (or time out) and cleanly kick off reconnection.

10. In `handle_frames`, add two new clauses: `{:ping, data}` → respond with `send_frame(state, {:pong, data})` (required by the WebSocket spec); `{:pong, _}` → no-op (acknowledgement that the server received our ping).

11. Cancel any scheduled ping timer before resetting state in both the stream error handler and the close frame handler, using `Process.cancel_timer(state.ping_timer)` guarded by a nil check.

### Phase 4 — Fix the "Live" badge in the LiveView

12. Add a `connected?/0` public function to `MempoolSocket` using `GenServer.call` that returns `state.websocket != nil`. This lets `MempoolLive` query the current status synchronously at mount time.

13. In `MempoolLive.mount`, when `connected?(socket)`, subscribe to both `"mempool:txids"` and `"mempool:status"`, then initialize `@connected` with `MempoolSocket.connected?()` rather than hardcoding `true`.

14. Add `handle_info({:socket_status, status}, socket)` in `MempoolLive` that assigns `@connected` to `status == :connected`.

---

## Relevant files

- `lib/btc_tx_feed/mempool_socket.ex` — all changes (struct, `handle_info/2`, `handle_continue/2`, `handle_frames/2`, `backoff_delay/1`, `connected?/0`)
- `lib/btc_tx_feed_web/live/mempool_live.ex` — mount subscription, `handle_info` for status message, initial `@connected` value
- `lib/btc_tx_feed/application.ex` — no changes needed

---

## Verification

1. Run `mix test` to confirm no regressions
2. In dev: confirm that manually killing/restarting the GenServer via IEx (`Process.whereis(BtcTxFeed.MempoolSocket) |> Process.exit(:kill)`) causes it to reconnect with visible backoff delays in logs
3. Confirm the "Live" badge goes to "Connecting…" when the socket is disconnected and back to "Live" once reconnected
4. Run `mix precommit` and resolve any issues

---

## Decisions

- Keepalive interval: 30s. Short enough to detect sleep quickly after wake, long enough not to produce noise. Can be adjusted.
- Max backoff cap: 30s. Prevents long outages from causing permanent slow reconnects.
- `{:stop, reason, state}` on initial connect failure is replaced with the same backoff-retry path — consistent behavior, and won't exhaust the supervisor's restart budget if mempool.space is down at startup.
- The `:connect` handler reuses `{:continue, :connect}` to avoid duplicating connection logic.
