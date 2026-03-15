# Plan: MVP 3 – Background Analytics Pipeline

## TL;DR

Introduce a background sampling pipeline that continuously decodes a rate-limited sample of
mempool transactions to battle-test `btc_tx`. Aggregate stats live in ETS (ephemeral). Decode
failures are persisted to SQLite so they survive redeploys and become regression vectors.
A new `/analytics` LiveView dashboard exposes both.

---

## Decisions

- **429 / HTTP errors** → drop silently. No re-queue. Not recorded as decode failures.
- **Decode failures** → persist to SQLite (survive redeploys).
- **Aggregate stats** → ETS only (reset on restart is acceptable).
- **Sampling rate** → 1 txid/sec, hard-coded for now.
- **Queue cap** → 500 txids. When full, drop oldest.
- **Fly.io storage** → SQLite on a persistent volume mounted at `/data`.

---

## Phase 1 – Dependencies & Ecto Setup

1. Add `{:ecto_sql, "~> 3.12"}` and `{:ecto_sqlite3, "~> 0.18"}` to `mix.exs` deps.
2. Create `lib/btc_tx_feed/repo.ex` — standard `Ecto.Repo` using `Ecto.Adapters.SQLite3`.
3. Add Repo config to `config/config.exs`:
   ```
   config :btc_tx_feed, BtcTxFeed.Repo,
     database: Path.expand("../btc_tx_feed.db", __DIR__)
   ```
4. Override in `config/runtime.exs` for production:
   ```
   config :btc_tx_feed, BtcTxFeed.Repo,
     database: System.get_env("DATABASE_PATH", "/data/btc_tx_feed.db")
   ```
5. Add test config to `config/test.exs` (file-backed DB required — `Ecto.Adapters.SQL.Sandbox` needs a persistent connection; `:memory:` is destroyed on connection close and loses the schema):
   ```
   config :btc_tx_feed, BtcTxFeed.Repo,
     database: Path.expand("../btc_tx_feed_test.db", __DIR__),
     pool: Ecto.Adapters.SQL.Sandbox
   ```
6. Add `BtcTxFeed.Repo` to the ecto_repos list in `config/config.exs`.

---

## Phase 2 – Failure Persistence (Ecto)

7. Create `lib/btc_tx_feed/failure.ex` — Ecto schema for `decode_failures`:
   - `txid :string` (nullable — may be nil if decode fails before txid is computable)
   - `raw_hex :string` (full raw bytes as lowercase hex — the regression vector)
   - `error_reason :string` (`inspect(reason)`)
   - `timestamps(updated_at: false)`

8. Generate migration `priv/repo/migrations/<timestamp>_create_decode_failures.exs`:
   - Creates `decode_failures` table with the fields above.
   - Adds index on `inserted_at` for the "last N" query.

9. Create `lib/btc_tx_feed/failure_store.ex` — thin wrapper with two functions:
   - `insert(txid, raw_bytes, reason)` — hex-encodes raw bytes, inserts row.
   - `list_recent(limit \\ 50)` — returns rows ordered by `inserted_at DESC`.

---

## Phase 3 – Aggregate Stats (ETS)

10. Create `lib/btc_tx_feed/tx_stats.ex` — GenServer owning a single ETS table.

    ETS keys tracked:
    - `:total_decoded`, `:total_failed`
    - `:segwit_count`, `:legacy_count`, `:coinbase_count`
    - `:validation_failure_count`
    - `{:version, v}` — e.g. `{:version, 2}`
    - `{:script_type, type}` — e.g. `{:script_type, :p2_t_r}`, one counter per output seen
    - `{:vsize_bucket, b}` — `:tiny` (<250), `:small` (250–500), `:medium` (500–1000), `:large` (1000–5000), `:oversized` (>5000)
    - `{:input_bucket, b}` — `:single` (1), `:few` (2–5), `:many` (>5)
    - `{:output_bucket, b}` — `:single` (1), `:few` (2–5), `:many` (>5)

    Public API:
    - `record(details_map)` — increments all relevant counters from a successful parse.
    - `record_failure()` — increments `:total_failed` only.
    - `get()` — returns a plain map of all counters for the dashboard.

---

## Phase 4 – Sampling Pipeline

11. Create `lib/btc_tx_feed/tx_sampler.ex` — GenServer.

    State: `%{queue: :queue.new(), queue_size: 0}`

    On `init`:
    - Subscribe to `mempool:txids` PubSub topic.
    - Schedule first `:tick` via `Process.send_after(self(), :tick, 1_000)`.

    On `{:new_txids, txids}` (from PubSub):
    - For each txid: if `queue_size < 500`, enqueue at back.
    - If queue is full (size == 500), drop the oldest (pop front) before pushing new one.

    On `:tick`:
    - Reschedule next `:tick` in 1000 ms unconditionally.
    - If queue is empty, return early.
    - Pop one txid from the front.
    - Spawn `Task.start/1`:
      ```
      case MempoolHttpClient.get_raw_tx(txid) do
        {:ok, raw} ->
          try do
            case TxParser.parse(raw) do
              {:ok, details} ->
                TxStats.record(details)
              {:error, reason} ->
                TxStats.record_failure()
                FailureStore.insert(nil, raw, reason)
            end
          rescue
            e ->
              TxStats.record_failure()
              FailureStore.insert(nil, raw, Exception.message(e))
          end
        {:error, _} ->
          # HTTP error / 429 — drop silently
          :ok
      end
      ```

    Note: HTTP errors are never recorded as decode failures — they are not `btc_tx` failures.
    The `try/rescue` around `TxParser.parse/1` catches unexpected exceptions from `btc_tx` API calls
    that succeed at the decode step but throw inside `build_details/1`.

---

## Phase 5 – Supervision

12. Update `lib/btc_tx_feed/application.ex` — add to children in this order:
    ```elixir
    BtcTxFeed.Repo,
    BtcTxFeed.TxStats,
    BtcTxFeed.TxSampler,
    ```
    Must come after `Phoenix.PubSub` (TxSampler subscribes to it) and before `Endpoint`.

---

## Phase 6 – Analytics UI

13. Create `lib/btc_tx_feed_web/live/analytics_live.ex`:
    - On `mount`: call `TxStats.get()`, assign as `@stats`. Schedule `:tick` via
      `:timer.send_interval(2_000, :refresh)` when `connected?(socket)`.
    - On `handle_info(:refresh, ...)`: re-call `TxStats.get()` and re-assign `@stats`.
    - Display (all derived from `@stats`):
      - Pass rate bar: `total_decoded / (total_decoded + total_failed)` as percentage.
      - Failure count with `<.link navigate={~p"/analytics/failures"}>` link.
      - Script type distribution: one Tailwind progress bar per script type,
        normalized to % of total output scripts seen.
      - vsize bucket distribution bars.
      - Version histogram.
      - Input/output count bucket bars.

14. Create `lib/btc_tx_feed_web/live/failures_live.ex`:
    - On `mount`: call `FailureStore.list_recent(50)`, stream into `@streams.failures`.
    - Each row shows: timestamp, txid (truncated with `…`), error reason.
    - Full `raw_hex` in a `<details>/<summary>` element (expandable, not shown by default).

15. Update `lib/btc_tx_feed_web/router.ex` — add routes inside the existing `/` scope:
    ```elixir
    live "/analytics", AnalyticsLive
    live "/analytics/failures", FailuresLive
    ```

---

## Phase 7 – Fly.io Volume Config

16. Add to `fly.toml` when deploying:
    ```toml
    [[mounts]]
      source = "btc_tx_feed_data"
      destination = "/data"
    ```
    The `DATABASE_PATH` env var (defaulting to `/data/btc_tx_feed.db`) set in `runtime.exs`
    points SQLite at the persistent volume. Run `fly volumes create btc_tx_feed_data` once
    before first deploy.

---

## Relevant Files

- `mix.exs` — add `ecto_sql` + `ecto_sqlite3` deps
- `config/config.exs` — Repo config + ecto_repos
- `config/runtime.exs` — production DATABASE_PATH override
- `config/test.exs` — file-backed SQLite + Sandbox pool
- `lib/btc_tx_feed/application.ex` — add Repo, TxStats, TxSampler to supervision tree
- `lib/btc_tx_feed_web/router.ex` — add `/analytics` and `/analytics/failures` routes
- `lib/btc_tx_feed/repo.ex` — **new**
- `lib/btc_tx_feed/failure.ex` — **new**
- `priv/repo/migrations/*_create_decode_failures.exs` — **new**
- `lib/btc_tx_feed/failure_store.ex` — **new**
- `lib/btc_tx_feed/tx_stats.ex` — **new**
- `lib/btc_tx_feed/tx_sampler.ex` — **new**
- `lib/btc_tx_feed_web/live/analytics_live.ex` — **new**
- `lib/btc_tx_feed_web/live/failures_live.ex` — **new**

---

## Verification

1. `mix deps.get` compiles cleanly with ecto_sqlite3 added.
2. `mix ecto.create && mix ecto.migrate` succeeds locally, creates `btc_tx_feed.db`.
3. Start app — `TxSampler` logs first `:tick` 1 second after boot.
4. After ~30 seconds, `TxStats.get()` from iex shows non-zero `total_decoded`.
5. Navigate to `/analytics` — stats update every 2 seconds without full page reload.
6. Navigate to `/analytics/failures` — renders (empty is fine if no failures yet).
7. Manually insert a failure row via `FailureStore.insert(...)` in iex, confirm it appears in the UI.
8. `mix test` passes (file-backed SQLite with SQL Sandbox used in test env).
9. `mix precommit` passes with no issues.
