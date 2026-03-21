# Plan: Session-based Stats History

## Core idea

A "session" = one continuous run of the app. On start, `TxStats` begins with **empty counters**.
On clean shutdown, the session's final counters are archived to SQLite. The snapshot file and all
related flush machinery are removed entirely.

> **Graceful shutdown requirement**: `terminate/2` is only invoked when the OTP supervision tree
> shuts down in an orderly way. To record a session locally, stop the server with
> `System.stop()` / `:init.stop()` (from an `iex -S mix phx.server` session) or
> `kill -TERM <pid>`. **Do not use Ctrl+C → a** (break menu abort) — that calls `erlang:halt/0`
> and bypasses the OTP shutdown sequence entirely.

---

## Step 1 — New DB table: `stats_sessions`

Migration for a `stats_sessions` table:

| Column | Type | Notes |
|---|---|---|
| `id` | integer PK | |
| `started_at` | utc_datetime | set when GenServer initializes |
| `ended_at` | utc_datetime, nullable | set on clean shutdown |
| `counters` | binary blob | `:erlang.term_to_binary/1` of the ETS map — consistent with existing snapshot format |
| `total_decoded` | integer | denormalized for fast list queries |
| `total_failed` | integer | denormalized for fast list queries |

The `counters` blob stores the full map so the history detail view can render the same stats
breakdowns as the current analytics page without any schema changes.

---

## Step 2 — `BtcTxFeed.StatsSession` schema + `BtcTxFeed.StatsSessions` context

- `StatsSession` — thin Ecto schema over `stats_sessions`
- `StatsSessions` context with:
  - `archive(counters_map, started_at, ended_at)` — called by `TxStats` on terminate
  - `list/0` — returns all sessions ordered by `started_at desc`, without loading the blob
  - `get!(id)` — loads the full row including `counters` blob for the detail view

---

## Step 3 — Modify `TxStats` GenServer

**`init/1`** — change startup behavior:
1. Keep `Process.flag(:trap_exit, true)` — required so the supervisor's shutdown signal triggers `terminate/2` rather than killing the process immediately
2. Start ETS with **empty counters** every time (remove `load_snapshot/0` call)
3. Record `started_at = DateTime.utc_now()` in the GenServer state

**`terminate/2`** — change shutdown behavior:
1. Call `StatsSessions.archive(counters, started_at, DateTime.utc_now())`
2. Remove the snapshot write

---

## Step 4 — Remove snapshot machinery

Delete all code and config related to the snapshot file:

- `TxStats`: remove `persist_snapshot/0`, `load_snapshot/0`, `schedule_flush/0`, the `:flush`
  `handle_info` clause, and the `@flush_interval` module attribute — keep `Process.flag(:trap_exit, true)` since `terminate/2` must still be invoked on clean shutdown
- `config/config.exs`: remove the `tx_stats_snapshot_path` config line
- `config/runtime.exs`: remove the `tx_stats_snapshot_path` prod override
- Delete the snapshot binary file from disk if one exists (`tx_stats_snapshot.bin`)

---

## Step 5 — New route + `SessionHistoryLive`

Add to the router:

```
/analytics/history        → SessionHistoryLive (list)
/analytics/history/:id    → SessionHistoryLive (detail, param-driven)
```

**List view** — table of past sessions: `started_at`, duration, `total_decoded`, `total_failed`,
pass rate. Rows are clickable links to the detail view.

**Detail view** — same stat card layout as `AnalyticsLive` but rendered from the archived
`counters` blob, with a "← Back to history" breadcrumb. Since the rendering helpers in
`AnalyticsLive` are pure functions of the stats map, extract them to a shared `StatsComponents`
module and reuse across both views.

---

## Step 6 — Update `AnalyticsLive`

Add a "View session history →" link next to (or below) the existing failures link, pointing to
`/analytics/history`.

---

## Step 7 — Tests

- `StatsSessions` context: archive + list + get roundtrip
- `TxStats` behaviour: verify ETS starts empty, verify `terminate` archives to DB
- `SessionHistoryLive`: renders list, renders detail with stat breakdowns

---

## What doesn't change

- The live stats polling loop in `AnalyticsLive` stays identical
- `TxStats.record/1` and `TxStats.record_failure/0` are unchanged
- The existing `failures_live.ex` page is unaffected
