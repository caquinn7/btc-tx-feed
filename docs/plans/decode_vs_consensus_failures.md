# Decode Failures vs Consensus Violations

Separate decode failures (transactions that could not be parsed) from consensus
violations (transactions that parsed successfully but failed Bitcoin consensus
validation). Each gets its own persistence path, dedicated LiveView page, and
navigation links.

---

## Motivation

Currently, consensus violations are not persisted at all. `TxParser` discards the
error list from `validate_consensus/1` and only sets `validated: false` on the
details map. `TxSampler` passes that to `TxStats.record/1`, which increments the
`validation_failure_count` ETS counter, but nothing is written to the database and
no UI exposes the errors.

Decode failures (transactions that could not be parsed) are persisted via
`FailureStore.insert/4` and displayed on the existing failures page. This plan
brings consensus violations to the same level of persistence and visibility, with
each failure mode getting its own page.

---

## Affected files

| File | Change |
|---|---|
| `priv/repo/migrations/` | New migration — add `failure_type` column |
| `lib/btc_tx_feed/failure.ex` | Add `failure_type` field to schema |
| `lib/btc_tx_feed/failure_store.ex` | Replace `insert/4` with typed insert functions and typed query functions |
| `lib/btc_tx_feed/tx_parser.ex` | Capture `validation_errors` instead of discarding them |
| `lib/btc_tx_feed/tx_sampler.ex` | Call the correct `FailureStore` insert function at each call site |
| `lib/btc_tx_feed_web/router.ex` | Replace single `/analytics/failures` route with two typed routes |
| `lib/btc_tx_feed_web/live/failures_live.ex` | Rename to `DecodeFailuresLive`, use typed store queries |
| `lib/btc_tx_feed_web/live/consensus_violations_live.ex` | New LiveView for consensus violations |
| `lib/btc_tx_feed_web/live/analytics_live.ex` | Update decode link path, add consensus violations link |
| `lib/btc_tx_feed_web/live/session_history_live.ex` | Update failures link path |
| `test/btc_tx_feed/failure_store_test.exs` | Update to typed insert/query functions |
| `test/btc_tx_feed_web/live/failures_live_test.exs` | Update paths and insert calls |
| `test/btc_tx_feed_web/live/analytics_live_test.exs` | Update path assertion |
| `test/btc_tx_feed_web/live/session_history_live_test.exs` | Update path assertion |

---

## Step-by-step

### 1. Migration — add `failure_type` column

New file: `priv/repo/migrations/20260327000001_add_failure_type_to_decode_failures.exs`

```elixir
defmodule BtcTxFeed.Repo.Migrations.AddFailureTypeToDecodeFailures do
  use Ecto.Migration

  def change do
    alter table(:decode_failures) do
      add :failure_type, :string, null: false, default: "decode"
    end
  end
end
```

The `default: "decode"` ensures all existing rows remain valid after the migration.

---

### 2. `Failure` schema

Add the field:

```elixir
field(:failure_type, :string)
```

---

### 3. `FailureStore`

Replace `insert/4`, `list_for_session/1`, and `list_recent/1` with typed
equivalents backed by a shared private helper:

```elixir
def insert_decode_failure(txid, raw_bytes, reason, session_id) do
  do_insert(txid, raw_bytes, reason, session_id, "decode")
end

def insert_consensus_failure(txid, raw_bytes, errors, session_id) do
  do_insert(txid, raw_bytes, errors, session_id, "consensus")
end

defp do_insert(txid, raw_bytes, reason, session_id, failure_type) do
  Repo.insert!(%Failure{
    txid: txid,
    raw_hex: Base.encode16(raw_bytes, case: :lower),
    error_reason: inspect(reason),
    stats_session_id: session_id,
    failure_type: failure_type
  })
  :ok
end

def list_decode_failures_for_session(session_id),
  do: list_by_type("decode", session_id: session_id)

def list_decode_failures_recent(limit \\ 50),
  do: list_by_type("decode", limit: limit)

def list_consensus_violations_for_session(session_id),
  do: list_by_type("consensus", session_id: session_id)

def list_consensus_violations_recent(limit \\ 50),
  do: list_by_type("consensus", limit: limit)

defp list_by_type(type, session_id: session_id) do
  Repo.all(
    from f in Failure,
      where: f.failure_type == ^type and f.stats_session_id == ^session_id,
      order_by: [desc: f.inserted_at]
  )
end

defp list_by_type(type, limit: limit) do
  Repo.all(
    from f in Failure,
      where: f.failure_type == ^type,
      order_by: [desc: f.inserted_at],
      limit: ^limit
  )
end
```

---

### 4. `TxParser` — capture `validation_errors`

In `build_details/1`, update the `validate_consensus` case:

- Success branch: add `validation_errors: []` to the merged map.
- Failure branch: capture the error list and include it in the map.

```elixir
{:ok, validated} ->
  Map.merge(base, %{
    validated: true,
    validation_errors: [],
    txid: be_hex(:btc_tx.compute_txid(validated)),
    ...
  })

{:error, validation_errors} ->
  base
  |> Map.put(:validated, false)
  |> Map.put(:validation_errors, validation_errors)
```

---

### 5. `TxSampler` — call the correct insert function

```elixir
{:ok, details} ->
  TxStats.record(details)

  unless details.validated do
    FailureStore.insert_consensus_failure(
      txid, raw, details.validation_errors, TxStats.get_session_id()
    )
  end

{:error, reason} ->
  TxStats.record_failure()
  FailureStore.insert_decode_failure(txid, raw, reason, TxStats.get_session_id())

# rescue block:
FailureStore.insert_decode_failure(txid, raw, Exception.message(e), TxStats.get_session_id())
```

---

### 6. Router — replace single route with two

```elixir
live "/analytics/failures/decode", DecodeFailuresLive
live "/analytics/failures/consensus", ConsensusViolationsLive
```

Remove `live "/analytics/failures", FailuresLive`.

---

### 7. `failures_live.ex` → `DecodeFailuresLive`

- Rename module to `BtcTxFeedWeb.DecodeFailuresLive`.
- In `mount/3`: call `FailureStore.list_decode_failures_for_session/1` and
  `FailureStore.list_decode_failures_recent/1`.
- Update `current_path` to `~p"/analytics/failures/decode"`.
- Page heading and copy remain as "Decode Failures".

---

### 8. New `consensus_violations_live.ex`

Same structure as `DecodeFailuresLive` but:

- Module: `BtcTxFeedWeb.ConsensusViolationsLive`.
- `mount/3`: calls `list_consensus_violations_for_session/1` /
  `list_consensus_violations_recent/1`.
- `current_path`: `~p"/analytics/failures/consensus"`.
- Page heading: **Consensus Violations**.
- Description copy: "Transactions that decoded successfully but failed Bitcoin
  consensus validation."

---

### 9. `AnalyticsLive` — update decode link, add consensus link

Update the existing failures link path and add a second link for consensus
violations driven by the `validation_failure_count` counter:

```heex
<% failed = Map.get(@stats, :total_failed, 0) %>
<.link navigate={~p"/analytics/failures/decode?session_id=#{@session_id}"} ...>
  {failed} decode {if failed == 1, do: "failure", else: "failures"} →
</.link>

<% consensus_failed = Map.get(@stats, :validation_failure_count, 0) %>
<.link navigate={~p"/analytics/failures/consensus?session_id=#{@session_id}"} ...>
  {consensus_failed} consensus {if consensus_failed == 1, do: "violation", else: "violations"} →
</.link>
```

---

### 10. `SessionHistoryLive` — update link

Change:

```
~p"/analytics/failures?session_id=#{@session.id}"
```

to:

```
~p"/analytics/failures/decode?session_id=#{@session.id}"
```

Update the surrounding copy ("decode failures") to remain accurate.

---

### 11. Tests

**`failure_store_test.exs`**
- Rename `describe "insert/4"` → `describe "insert_decode_failure/4"`.
- Replace all `FailureStore.insert(...)` calls with `FailureStore.insert_decode_failure(...)`.
- Replace `list_for_session/1` calls with `list_decode_failures_for_session/1`.
- Add a test asserting `failure_type` is `"decode"` for decode failures and
  `"consensus"` for consensus failures.

**`failures_live_test.exs`**
- Update all `~p"/analytics/failures"` paths to `~p"/analytics/failures/decode"`.
- Replace `FailureStore.insert(...)` with `FailureStore.insert_decode_failure(...)`.

**`analytics_live_test.exs`**
- Update href assertion:
  `/analytics/failures?session_id=` → `/analytics/failures/decode?session_id=`.

**`session_history_live_test.exs`**
- Update href assertion:
  `/analytics/failures?session_id=` → `/analytics/failures/decode?session_id=`.

---

## Acceptance criteria

1. `mix ecto.migrate` runs without errors.
2. Existing rows in `decode_failures` retain `failure_type = "decode"`.
3. `TxParser.parse/1` returns `validation_errors: []` on success and a populated
   list on failure.
4. `TxSampler` writes decode failures to `failure_type = "decode"` rows and
   consensus violations to `failure_type = "consensus"` rows.
5. `/analytics/failures/decode` and `/analytics/failures/consensus` render
   correctly, with and without `?session_id`.
6. The old `/analytics/failures` route no longer exists.
7. `mix test` passes.
