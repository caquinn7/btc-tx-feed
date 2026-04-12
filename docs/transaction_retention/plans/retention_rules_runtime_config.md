# Plan: Retention Rules Runtime Configuration

## TL;DR

Load retention rules from a file on the Fly.io persistent volume (`/data/retention_rules.exs`) at startup via `runtime.exs`, so rules can be changed and applied with a machine restart rather than a full build and deploy.

---

## Background

The `BtcTxFeed.TxRetentionRules` DSL and `BtcTxFeed.TxParser` enriched output are both in place. The missing pieces are:

1. A loading strategy so rules are available at runtime
2. Startup validation so a bad rules file fails fast
3. A thin accessor so future callers have a clean call site

Retention rules have no bearing on stats recording or failure recording — those happen unconditionally for all transactions. Rules gate a separate retention action (e.g. saving a transaction to a corpus) that will be wired up in a subsequent plan.

---

## Goals

- Rules are read once at startup and never change while the app is running
- Changing rules requires only a machine restart, not a build or deploy
- A missing or empty rules file is a valid state (no transactions are retained)
- A malformed rules file crashes startup with a clear error message
- Stats recording and failure recording are **not affected** by rules
- Works identically in dev/test without needing a file on disk

## Non-goals

- Hot-reloading rules while the app is running
- A UI or LiveView editor for rules
- Persisting rules to the SQLite database
- Per-session or per-source rule sets

---

## Approach

Use the existing Fly.io persistent volume (already mounted at `/data` for the SQLite database). Place a rules file at `/data/retention_rules.exs`. `runtime.exs` reads it at startup if it exists and sets the application env. `Application.start/2` validates all rules before the supervisor tree starts.

This follows the same pattern already used in `runtime.exs` for `:decode_policy`.

---

## Changes

### 1. `config/config.exs` — compile-time default

Add an empty default so the app boots cleanly on a fresh environment where no rules file exists yet:

```elixir
config :btc_tx_feed, :retention_rules, []
```

### 2. `config/runtime.exs` — volume file loading

```elixir
rules_path = System.get_env("RETENTION_RULES_PATH", "/data/retention_rules.exs")

if File.exists?(rules_path) do
  {rules, _bindings} = Code.eval_file(rules_path)
  config :btc_tx_feed, :retention_rules, rules
end
```

`RETENTION_RULES_PATH` allows overriding the path if needed. The default is `/data/retention_rules.exs`, which works both on Fly.io and locally if you maintain a `data/retention_rules.exs` file in the project.

### 3. `lib/btc_tx_feed/application.ex` — startup validation

Call a validation step before the supervisor tree starts, immediately after `maybe_migrate/0`:

```elixir
def start(_type, _args) do
  setup_signal_handlers()
  maybe_migrate()
  validate_retention_rules!()

  children = [...]
  ...
end

defp validate_retention_rules! do
  rules = Application.get_env(:btc_tx_feed, :retention_rules, [])

  Enum.each(rules, fn rule ->
    case BtcTxFeed.TxRetentionRules.validate_rule(rule) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Invalid retention rule in config: #{reason}\n  Rule: #{inspect(rule)}"
    end
  end)
end
```

Raising here terminates the startup process with a clear message in logs before any supervised process starts.

### 4. `lib/btc_tx_feed/retention_config.ex` — new accessor module

A plain module (no GenServer, no process) that reads the already-validated application env:

```elixir
defmodule BtcTxFeed.RetentionConfig do
  def rules do
    Application.get_env(:btc_tx_feed, :retention_rules, [])
  end

  def any_match?(details) do
    Enum.any?(rules(), &BtcTxFeed.TxRetentionRules.match?(details, &1))
  end
end
```

Rules are disjunctive: a transaction is retained if **any** rule matches. If no rules are configured, `any_match?/1` returns `false` and no transactions are retained.

---

## The rules file format

`/data/retention_rules.exs` is a bare Elixir expression — no `import Config`, no module wrapper:

```elixir
[
  {:all, [
    {:eq, :is_segwit, true},
    {:has_output_script_type, :null_data}
  ]},
  {:gte, :input_count, 3}
]
```

The file must evaluate to a list. Each element is an independent rule; a transaction matching any one of them is retained.

---

## Operator workflow (Fly.io)

To update rules without a deploy:

```sh
# Open a shell into the running container
fly ssh console

# Edit or create the rules file on the volume
vi /data/retention_rules.exs

# Exit the shell, then restart the machine
fly machine restart
```

The machine comes back up in seconds and picks up the new rules. If the file is malformed, the startup crash will appear in `fly logs` immediately.

---

## File touch points

| File | Change |
|---|---|
| `config/config.exs` | Add `config :btc_tx_feed, :retention_rules, []` |
| `config/runtime.exs` | Add file-loading block |
| `lib/btc_tx_feed/application.ex` | Add `validate_retention_rules!/0` |
| `lib/btc_tx_feed/retention_config.ex` | New accessor module |
| `test/btc_tx_feed/retention_config_test.exs` | Tests for accessor behaviour |

---

## Testing approach

- `RetentionConfig.any_match?/1` with no rules configured returns `false`
- `RetentionConfig.any_match?/1` with a matching rule returns `true`
- `RetentionConfig.any_match?/1` with a non-matching rule returns `false`

For testing `runtime.exs` loading behaviour, set `RETENTION_RULES_PATH` to a temp file path rather than relying on `/data`.

---

## Verification checklist

1. `config/config.exs` default empty list boots the app cleanly with no rules file present
2. Setting `RETENTION_RULES_PATH` to a valid `.exs` file loads the rules correctly
3. Setting `RETENTION_RULES_PATH` to a malformed file raises on startup with a readable error
4. Stats and failure recording are unaffected — all transactions continue to flow through the existing pipeline
5. `mix test` and `mix precommit` pass

---

## Deferred

- Wiring `RetentionConfig.any_match?/1` into `TxSampler` once a concrete retention action (e.g. corpus store) exists
- Hot-reloading rules without a restart
- Storing rules in SQLite and loading from there
- A LiveView UI for rule editing
- Rule priority ordering or named rules
