# Plan: Session-scoped Decode Failures

## Core idea

Associate each `decode_failures` row with the session in which it occurred. The live analytics
page shows only current-session failures; the history detail view shows only that session's
failures.

Because this requires linking failures to a session at write time, the session row must exist in
the DB **before** any failures are recorded. This means the `stats_sessions` lifecycle must shift
from insert-on-terminate to a two-phase approach:

1. **On `TxStats.init/1`**: INSERT an open session row (`started_at` only); store the returned
   `id` in GenServer state.
2. **On `TxStats.terminate/2`**: UPDATE that row with `counters`, `total_decoded`,
   `total_failed`, `ended_at`.

---

## Step 1 — Migration: truncate failures + add `stats_session_id` FK

Create a new migration (timestamped after `20260321000000_create_stats_sessions.exs`) that:

1. `DELETE FROM decode_failures` — clears pre-association rows from before sessions were
   tracked. These rows already exist on fly.io and cannot be linked to any session.
2. `ALTER TABLE decode_failures ADD COLUMN stats_session_id INTEGER REFERENCES stats_sessions(id)`
   — adds the nullable FK column.

`down/0` only needs to remove the column; restoring deleted rows is not required.

---

## Step 2 — Update `Failure` schema

Add `field(:stats_session_id, :integer)` to `BtcTxFeed.Failure`.

---

## Step 3 — Update `StatsSessions` context

Replace `archive!/3` with two new functions:

| Function | Behaviour |
|---|---|
| `create_open!(started_at)` | INSERT row with only `started_at` set; returns `%StatsSession{}` with the new `id` |
| `finalize!(id, counters, ended_at)` | UPDATE the row: set `ended_at`, `counters`, `total_decoded`, `total_failed` |

Update `list/0` to add `WHERE ended_at IS NOT NULL` so the in-progress session is excluded from
the history table.

---

## Step 4 — Update `TxStats` GenServer

**`init/1`**: call `StatsSessions.create_open!(DateTime.utc_now())`, store `:session_id` from
the returned struct in GenServer state alongside `:started_at`.

**`terminate/2`**: call `StatsSessions.finalize!(session_id, counters, DateTime.utc_now())`
instead of `archive!/3`.

**New public function** `get_session_id/0`: `GenServer.call(__MODULE__, :get_session_id)`,
backed by a `handle_call(:get_session_id, _, state)` clause that returns
`{:reply, state.session_id, state}`.

---

## Step 5 — Update `FailureStore`

- `insert/4`: add a `session_id` parameter and persist it to the `stats_session_id` column.
- `list_for_session/1`: returns all failures for a given `session_id` ordered `desc` by
  `inserted_at`.
- `list_recent/1` can be removed once no longer called.

---

## Step 6 — Update `TxSampler`

Change both `FailureStore.insert/3` call sites to
`FailureStore.insert(txid, raw, reason, TxStats.get_session_id())`.

---

## Step 7 — Update `FailuresLive`

Accept an optional `session_id` integer query parameter:

- **When present**: load failures with `FailureStore.list_for_session(session_id)`. Use
  `Integer.parse/1` on the raw param and redirect to `/analytics` on invalid input. The back
  link should navigate to `/analytics/history/:id` if the session is finalized (`ended_at` is
  set) or to `/analytics` if it is still open. Determine this by calling
  `StatsSessions.get!(session_id)` and checking `ended_at`.
- **When absent**: fall back to `FailureStore.list_recent(50)` (existing behaviour, kept for
  backward compatibility).

---

## Step 8 — Update `AnalyticsLive`

- Add `assign(:session_id, TxStats.get_session_id())` in `mount/3`.
- Change the failures link to `~p"/analytics/failures?session_id=#{@session_id}"` so it
  navigates to the current-session-scoped view.

---

## Step 9 — Update `SessionHistoryLive` detail view

`session.total_failed` already holds the count (stored when the session was finalized) — no
extra DB query needed. In the `:show` render, add a failures link alongside the stats:

```
{session.total_failed} decode {failure/failures} →
```

pointing to `~p"/analytics/failures?session_id=#{@session.id}"`.

---

## Step 10 — Tests

- `StatsSessions` context: `create_open! + finalize!` roundtrip; verify `list/0` excludes open
  sessions.
- `TxStats` behaviour: verify `get_session_id/0` returns the DB row ID; verify `terminate/2`
  finalizes the row.
- `FailureStore`: `insert/4` persists `stats_session_id`; `list_for_session/1` scopes correctly.
- `AnalyticsLive`: failures link includes `?session_id` param matching the current session.
- `FailuresLive`: renders session-scoped failures when `?session_id` is present; back link
  routes to `/analytics/history/:id` for closed sessions and `/analytics` for the open session.
- `SessionHistoryLive` detail: renders the failure count link with the correct `session_id`.
