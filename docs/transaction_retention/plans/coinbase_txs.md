# Plan: Coinbase Transaction Retention via Block Polling

## TL;DR
Add a `CoinbaseSampler` GenServer that periodically polls `mempool.space /api/blocks`, identifies unseen blocks, fetches the coinbase tx (index 0) for each, parses it, and runs it through the existing retention pipeline. Two new HTTP helpers needed in `MempoolHttpClient`. Wired into `analytics_children()` in `Application`.

---

## Phase 1: Extend MempoolHttpClient

Add two new functions to `lib/btc_tx_feed/mempool_http_client.ex`:

1. `get_recent_blocks/0` — `GET https://mempool.space/api/blocks`
   - Returns `{:ok, [%{"id" => block_hash, ...}]}` or `{:error, ...}`
   - Decode JSON body (Req handles this automatically)

2. `get_block_txid/2` — `GET https://mempool.space/api/block/:hash/txid/:index`
   - Returns `{:ok, txid_string}` or `{:error, ...}`
   - Response is plain text (a 64-char hex string)
   - Same error handling pattern: `{:error, {:http_error, status}}` on non-200

## Phase 2: DB Migration + SeenBlockStore

**Migration**: create `seen_blocks` table
- `block_hash` string, unique index
- `inserted_at` timestamp (no `updated_at`)

**New module**: `lib/btc_tx_feed/seen_block_store.ex` (mirrors pattern of `FailureStore`, `RetainedTxStore`)
- `all_hashes/0` → returns `MapSet.t(String.t())` (loaded on GenServer init)
- `insert!/1` → inserts `block_hash`, no-ops on conflict (use `on_conflict: :nothing`)

## Phase 3: Create CoinbaseSampler GenServer

New file: `lib/btc_tx_feed/coinbase_sampler.ex`

**State**: `%{seen_block_ids: MapSet.new(), resume_at: nil}`

**Init**: Load `seen_block_ids = SeenBlockStore.all_hashes()`. Schedule first poll. Subscribe to nothing — self-polling only.

**Tick interval**: 60 seconds (`@tick_ms 60_000`) — new blocks ~every 10 min so 60s gives ~10x polling, acceptable.

**`handle_info(:tick, state)` logic**:
1. Skip if inside backoff window (`resume_at`)
2. Call `MempoolHttpClient.get_recent_blocks()`
3. Filter out block IDs already in `seen_block_ids`
4. For each new block ID (process synchronously in the tick, at most ~10 on first run, typically 0-1):
   - Call `MempoolHttpClient.get_block_txid(block_id, 0)`
   - On `{:ok, txid}` → call `MempoolHttpClient.get_raw_tx(txid)` (already exists)
   - On `{:ok, raw}` → `TxParser.parse(raw)` (wrap in try/rescue)
   - On parse `{:ok, details}` → run `RetentionConfig.matching_entries(details)` → `RetainedTxStore.insert!(txid, raw, entry)` for each match
   - On parse `{:error, reason}` → `FailureStore.insert_decode_failure!(txid, raw, reason, TxStats.get_session_id())`
   - Mark block_id as seen via `SeenBlockStore.insert!(block_id)` + add to `seen_block_ids` **only after** successful raw fetch (transient errors retry next poll; other HTTP errors log and mark seen to avoid loops)
5. On 429 from any HTTP call → send `self()` `:backoff`, stop processing remaining blocks

**Key differences from TxSampler**:
- No `TxStats.record/1` — coinbase txs would skew mempool stats
- No consensus failure path — `TxStats.get_session_id()` used only for decode failures
- Processes synchronously in the tick (not via `Task.start`) — at most 1 new block per tick normally, 10 on first start

## Phase 4: Wire into Supervision Tree

In `lib/btc_tx_feed/application.ex`, add `BtcTxFeed.CoinbaseSampler` to `analytics_children/0` list (after `TxSampler`).

## Relevant Files
- `lib/btc_tx_feed/mempool_http_client.ex` — add `get_recent_blocks/0` and `get_block_txid/2`
- `lib/btc_tx_feed/seen_block_store.ex` — new store module
- `lib/btc_tx_feed/coinbase_sampler.ex` — new GenServer (new file)
- `lib/btc_tx_feed/application.ex` — add to `analytics_children/0`
- New migration under `priv/repo/migrations/`

## Verification
1. `mix compile` — no warnings
2. Unit test: mock HTTP calls, verify `seen_block_ids` grows, verify `RetainedTxStore.insert!` called for matching txs
3. Manual: run `mix phx.server`, check logs for "CoinbaseSampler: fetched coinbase" messages
4. `mix precommit` — all checks pass

## Decisions / Tradeoffs
- **Seen blocks persist to DB** — `SeenBlockStore` with `on_conflict: :nothing`; in-memory `MapSet` loaded at init for fast lookups; clean restart behavior with no duplicates
- **No TxStats recording** — avoids skewing mempool stats with coinbase txs
- **Synchronous processing in tick** — acceptable because at most 1-2 new blocks per tick. If blocking becomes an issue, move to `Task.start` like TxSampler
- **Mark seen on successful HTTP fetch, not parse success** — avoids re-fetching on parse errors; parse failures go to `FailureStore`
