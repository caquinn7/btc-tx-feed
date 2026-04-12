# Plan: Retained Transactions Persistence (v2)

## TL;DR

Revise the v1 retention plan to use **corpus-code-based, per-code caps**
instead of first-match-wins. A transaction can be retained under multiple
corpus codes if it satisfies multiple rules. Each corpus code has its own
storage limit. The raw file format and in-memory config structure both change
to carry the code, label, and limit alongside the rule.

---

## What changed since v1

| Concern | v1 design | v2 design |
|---|---|---|
| Config entry shape | bare rule tuple | `%{code, label, limit, rule}` map |
| Matching strategy | first match wins, store once | all matching entries, store per code |
| Primary key | `txid` alone | composite `(txid, corpus_code)` |
| Stored columns | `txid`, `raw_hex`, `matched_rule` | `txid`, `corpus_code`, `corpus_label`, `raw_hex`, `matched_rule` |
| Per-code cap | not enforced | enforced at insert time |
| Dedup within same code | `on_conflict: :nothing` | not explicitly enforced; feed is assumed to emit each txid once |

---

## Goals

- A validated transaction is stored once **per matching corpus code** that is
  still below its limit
- Corpus code and label are persisted alongside the rule for human-readable
  recall without needing the config file
- Per-code limits are enforced at insert time via a count check
- The existing decode/stats/failure pipeline is unaffected
- The rules file format is updated to the new map shape
- `RetentionConfig` is updated to expose matching corpus entries, not raw rules

## Non-goals

- Querying or displaying retained transactions in a LiveView (separate plan)
- Pruning or expiry of retained rows
- Same-code dedup (trusted feed; deferred if needed)
- Hot-reloading or editing rules at runtime

---

## Config entry shape

Each entry in the rules file is now a map:

```elixir
%{
  code: "F01",
  label: "OP_RETURN output present",
  limit: 50,
  rule: {:has_output_script_type, :null_data}
}
```

Entries are evaluated in declaration order. A transaction is checked against
**all** entries, not just the first match.

### Example `data/retention_rules.exs`

```elixir
[
  %{
    code: "F01",
    label: "OP_RETURN output present",
    limit: 50,
    rule: {:has_output_script_type, :null_data}
  },
  %{
    code: "C02",
    label: "Legacy multi-input",
    limit: 100,
    rule: {:all, [
      {:eq, :is_segwit, false},
      {:gte, :input_count, 2}
    ]}
  },
  %{
    code: "S06",
    label: "Witness-heavy transaction",
    limit: 25,
    rule: {:witness_total_bytes_gte, 500}
  }
]
```

---

## Schema

**Table: `retained_transactions`**

| Column | Type | Notes |
|---|---|---|
| `id` | integer, PK | Surrogate — simplest given composite uniqueness is not strictly enforced |
| `txid` | string, not null | Transaction identifier |
| `corpus_code` | string, not null | e.g. `"F01"` |
| `corpus_label` | string, not null | Human-readable label from config at retention time |
| `raw_hex` | string, not null | Full transaction hex |
| `matched_rule` | string, not null | `inspect(entry.rule)` — audit snapshot |
| `inserted_at` | utc_datetime | Immutable; no `updated_at` |

Indexes:
- Primary key on `id`
- Index on `corpus_code` (for cap count queries)
- Index on `inserted_at` (consistent with decode_failures pattern)

> **Why not composite PK on `(txid, corpus_code)`?**  
> SQLite supports composite PKs but Ecto requires more ceremony. Using a
> surrogate `id` keeps the schema and changeset straightforward. Since we
> trust the feed not to repeat txids, explicit same-code dedup is not needed
> in v1.

---

## Changes required

### 1. Migration

```elixir
defmodule BtcTxFeed.Repo.Migrations.CreateRetainedTransactions do
  use Ecto.Migration

  def change do
    create table(:retained_transactions) do
      add :txid, :string, null: false
      add :corpus_code, :string, null: false
      add :corpus_label, :string, null: false
      add :raw_hex, :string, null: false
      add :matched_rule, :string, null: false
      timestamps(updated_at: false)
    end

    create index(:retained_transactions, [:corpus_code])
    create index(:retained_transactions, [:inserted_at])
  end
end
```

### 2. `lib/btc_tx_feed/retained_transaction.ex` — Ecto schema

```elixir
defmodule BtcTxFeed.RetainedTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "retained_transactions" do
    field :txid, :string
    field :corpus_code, :string
    field :corpus_label, :string
    field :raw_hex, :string
    field :matched_rule, :string
    timestamps(updated_at: false)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:txid, :corpus_code, :corpus_label, :raw_hex, :matched_rule])
    |> validate_required([:txid, :corpus_code, :corpus_label, :raw_hex, :matched_rule])
  end
end
```

### 3. `config/runtime.exs` — validate new entry shape

The existing validation check (list assertion) must also verify that each
entry is a map with the required keys:

```elixir
if File.exists?(rules_path) do
  {entries, _bindings} = Code.eval_file(rules_path)

  if not is_list(entries) do
    raise "#{rules_path} must evaluate to a list, got: #{inspect(entries)}"
  end

  Enum.each(entries, fn entry ->
    required = [:code, :label, :limit, :rule]

    missing = Enum.reject(required, &Map.has_key?(entry, &1))

    if missing != [] do
      raise "retention_rules entry is missing keys #{inspect(missing)}: #{inspect(entry)}"
    end
  end)

  config :btc_tx_feed, :retention_rules, entries
end
```

### 4. `lib/btc_tx_feed/retention_config.ex` — replace `any_match?/1` with `matching_entries/1`

The config module returns the list of entry maps that matched, not just a
boolean or the first rule:

```elixir
defmodule BtcTxFeed.RetentionConfig do
  alias BtcTxFeed.TxRetentionRules

  def entries do
    Application.get_env(:btc_tx_feed, :retention_rules, [])
  end

  @doc """
  Returns all configured corpus entries whose rule matches `details`.
  Returns an empty list when no rules are configured or none match.
  Entries are returned in declaration order.
  """
  def matching_entries(details) do
    Enum.filter(entries(), fn %{rule: rule} ->
      TxRetentionRules.match?(details, rule)
    end)
  end
end
```

`any_match?/1` is no longer needed — callers check `matching_entries/1 != []`
if they need a boolean.

### 5. `lib/btc_tx_feed/retained_tx_store.ex` — new store module

Exposes a single `insert/4` that enforces the per-code cap before inserting:

```elixir
defmodule BtcTxFeed.RetainedTxStore do
  import Ecto.Query
  alias BtcTxFeed.{Repo, RetainedTransaction}

  @doc """
  Inserts a retained transaction row for the given corpus entry if the
  per-code limit has not yet been reached. Returns `:ok` in both cases.
  """
  def insert(txid, raw_bytes, entry) do
    count = Repo.aggregate(
      from(r in RetainedTransaction, where: r.corpus_code == ^entry.code),
      :count
    )

    if count < entry.limit do
      attrs = %{
        txid: txid,
        corpus_code: entry.code,
        corpus_label: entry.label,
        raw_hex: Base.encode16(raw_bytes, case: :lower),
        matched_rule: inspect(entry.rule)
      }

      attrs
      |> RetainedTransaction.changeset()
      |> Repo.insert()
    end

    :ok
  end
end
```

> **Cap enforcement note:** the count check is non-atomic (check-then-insert).
> Under the current `TxSampler` design — one tx processed per second in a
> single Task — this is safe. If concurrency increases, a unique partial index
> or a serialized GenServer call would be needed. Defer until then.

### 6. `lib/btc_tx_feed/tx_sampler.ex` — wire in retention

Inside `process/2`, after `TxStats.record(details)` and the consensus failure
check, iterate over all matching entries and attempt a store per code:

```elixir
if details.validated do
  details
  |> RetentionConfig.matching_entries()
  |> Enum.each(fn entry ->
    RetainedTxStore.insert(details.txid, raw, entry)
  end)
end
```

---

## File touch points

| File | Change |
|---|---|
| `priv/repo/migrations/TIMESTAMP_create_retained_transactions.exs` | New migration (surrogate PK, corpus_code, corpus_label) |
| `lib/btc_tx_feed/retained_transaction.ex` | New Ecto schema |
| `config/runtime.exs` | Validate new map shape per entry |
| `lib/btc_tx_feed/retention_config.ex` | Replace `any_match?/1` with `matching_entries/1`; rename `rules/0` to `entries/0` |
| `lib/btc_tx_feed/retained_tx_store.ex` | New store module with per-code cap logic |
| `lib/btc_tx_feed/tx_sampler.ex` | Wire per-code retention after `TxStats.record/1` |
| `test/btc_tx_feed/retained_tx_store_test.exs` | New store tests |
| `test/btc_tx_feed/retention_config_test.exs` | Tests for `matching_entries/1` |
| `data/retention_rules.exs` | Update to new map entry format (if file already exists) |

---

## Testing approach

**`RetentionConfig.matching_entries/1`**
- Returns `[]` when no entries are configured
- Returns all entries whose rules match
- Returns `[]` when entries exist but none match
- Returns multiple entries when a tx satisfies more than one rule

**`RetainedTxStore.insert/4`**
- Inserts a row when the code is under its limit; returns `:ok`
- Does not insert when the code is at its limit; returns `:ok`
- Stored columns match the entry's `code`, `label`, and `inspect(rule)`

**`TxSampler` integration**
- A validated tx matching two rules results in two rows (different `corpus_code`)
- A validated tx matching no rules inserts no rows
- A non-validated tx inserts no rows regardless of rules
- Stats and failure recording are unaffected

---

## Verification checklist

1. `mix ecto.migrate` runs cleanly
2. A tx matching two corpus codes produces two `retained_transactions` rows
3. A tx matching a code whose count is already at the limit is not inserted
4. Non-validated transactions produce no row
5. `corpus_code`, `corpus_label`, and `matched_rule` are populated correctly
6. Stats and `decode_failures` recording are unaffected
7. `mix test` and `mix precommit` pass
