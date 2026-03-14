# Plan: Extract WebSocketClient Module (Option A)

**TL;DR:** Pull all Mint/WebSocket plumbing out of `MempoolSocket` into a new pure-module `BtcTxFeed.WebSocketClient`. The GenServer stays single-process; the Mint handles move into a nested `%WebSocketClient{}` sub-struct on the GenServer state. `MempoolSocket` shrinks to application logic only: txid buffering, PubSub broadcasts, keepalive scheduling, and backoff timing.

---

## Struct split

**`WebSocketClient` struct** — pure Mint handles:
```
conn, websocket, request_ref, status, resp_headers
```

**`MempoolSocket` struct** — process-level state:
```
socket (%WebSocketClient{} | nil), txids, retry_count, ping_timer
```

`retry_count` and `ping_timer` stay in `MempoolSocket` because they drive `Process.send_after` scheduling, which is a GenServer concern, not a Mint concern.

---

## Steps

### Phase 1 — Create `WebSocketClient`

1. Create `lib/btc_tx_feed/websocket_client.ex` with:
   - `defstruct [:conn, :websocket, :request_ref, :status, :resp_headers]`
   - `connect(url)` — opens `Mint.HTTP.connect` + `Mint.WebSocket.upgrade`. Returns `{:ok, t()}` or `{:error, reason}`.
   - `send_frame(client, frame)` — wraps `Mint.WebSocket.encode` + `Mint.WebSocket.stream_request_body`. Returns `{:ok, t()}` or `{:error, t(), reason}`.
   - `stream(client, message)` — calls `Mint.WebSocket.stream`, reduces over raw HTTP upgrade responses (`{:status}`, `{:headers}`, `{:done}`) to advance internal state, then decodes any `{:data}` frames. Handles `{:ping}` → pong internally. Returns `{:ok, t(), [event]}`, `{:error, reason}`, or `:unknown`. Events are: `:connected`, `{:text, text}`, `{:close, reason}`.
   - `close(client)` — calls `Mint.HTTP.close(client.conn)`.
   - `connected?(client)` — returns `client.websocket != nil`.

2. The private HTTP-upgrade response reduction (`handle_response` clauses for `:status`, `:headers`, `:done`) lives inside `stream/2` as private helpers in `WebSocketClient`. The `Mint.WebSocket.new` call that transitions to websocket mode lives here too.

### Phase 2 — Rework `MempoolSocket`

3. Replace the `defstruct` in `MempoolSocket` with `[:socket, txids: [], retry_count: 0, ping_timer: nil]`. `socket` holds a `%WebSocketClient{}` once connected, `nil` until then.

4. In `handle_continue(:connect, state)`:
   - Call `WebSocketClient.connect("wss://mempool.space/api/v1/ws")`.
   - On `{:ok, client}`: return `{:noreply, %{state | socket: client}}` (keep `Process.send_after(self(), :flush, 100)` here).
   - On `{:error, reason}`: same backoff logic as today, using `state.retry_count`.

5. Replace the catch-all `handle_info(message, state)` stream dispatch:
   - Call `WebSocketClient.stream(state.socket, message)`.
   - On `{:ok, client, events}`: update `state.socket` to `client`, then process events:
     - `:connected` → broadcast `{:socket_status, :connected}`, reset `retry_count: 0`, schedule keepalive timer.
     - `{:text, text}` → decode JSON, accumulate into `state.txids`.
     - `{:close, reason}` → cancel ping timer, broadcast `:disconnected`, schedule backoff `:connect`.
   - On `{:error, reason}`: cancel ping timer, broadcast `:disconnected`, schedule backoff `:connect`.
   - On `:unknown`: no-op.

6. In `handle_info(:keepalive, state)`:
   - Call `WebSocketClient.send_frame(state.socket, {:ping, ""})`.
   - On `{:ok, client}`: store updated `state.socket`, reschedule timer.
   - On `{:error, ...}`: broadcast `:disconnected`, schedule backoff `:connect`.

7. In `handle_info(:connect, state)`:
   - Cancel ping timer.
   - Call `WebSocketClient.close(state.socket)` if `state.socket` is non-nil.
   - Reset to `%__MODULE__{retry_count: state.retry_count}`, continue `:connect`.

8. Update `handle_call(:connected?, ...)` to delegate to `WebSocketClient.connected?(state.socket)` (guard for `nil` socket).

9. Delete all private functions now moved to `WebSocketClient`: `handle_response/2` clauses, `handle_frames/2`, `send_frame/2`, and `backoff_delay/1`. Keep `backoff_delay/1` in `MempoolSocket` since it drives process scheduling there.

### Phase 3 — Verify and clean up

10. Run `mix compile` and fix any warnings.
11. Run `mix test` to confirm no regressions.
12. Run `mix precommit` and address any issues.

---

## Relevant files

- `lib/btc_tx_feed/websocket_client.ex` — **new file**: struct + all Mint/WebSocket plumbing
- `lib/btc_tx_feed/mempool_socket.ex` — reworked to delegate to `WebSocketClient`, owns only process scheduling and application logic

---

## Interface contract for `WebSocketClient`

```
connect(url :: String.t()) :: {:ok, t()} | {:error, reason}

send_frame(client :: t(), frame :: term()) ::
  {:ok, t()} | {:error, t(), reason}

stream(client :: t(), message :: term()) ::
  {:ok, t(), [event]} | {:error, reason} | :unknown

close(client :: t()) :: :ok

connected?(client :: t() | nil) :: boolean()
```

Where `event` is one of: `:connected`, `{:text, binary()}`, `{:close, reason}`.

Ping frames from the server are handled internally in `stream/2` (pong sent immediately); they are never surfaced as events to `MempoolSocket`.

---

## Decisions

- `retry_count` and `ping_timer` remain in `MempoolSocket` — they are scheduling state, not Mint state.
- `backoff_delay/1` remains in `MempoolSocket` for the same reason.
- No new process is introduced — the GenServer stays single-process.
- `WebSocketClient` is a pure module: no `use GenServer`, no PubSub, no `Logger` calls. All side effects stay in `MempoolSocket`.
- On `:connected` event, `MempoolSocket` is responsible for sending the mempool subscription frame (`{"track-mempool-txids": true}`) via `WebSocketClient.send_frame/2` — this is application logic, not protocol logic.
- `WebSocketClient.connected?/1` accepts `nil` and returns `false` to simplify the `handle_call` guard in `MempoolSocket`.
