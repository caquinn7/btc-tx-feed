# Plan: Capture coinbase transactions with large scriptSig

## Goal

Add a retention rule (`B01`) that captures a coinbase transaction when any of its inputs has a `scriptSig` whose byte length is near or at the Bitcoin protocol upper bound of 100 bytes (threshold: ≥ 80 bytes).

## Background

The existing DSL in `TxRetentionRules` exposes top-level summary scalars for
comparing per-input/output data — for example `largest_witness_item_bytes` and
`largest_script_pubkey_bytes`. These are derived once in `TxParser.parse/1` and
stored as flat keys in the `details_map`, making them immediately addressable by
the existing scalar comparison operators.

Per-input `script_sig_length` is already extracted inside `extract_inputs/1`
(via `:btc_tx.get_script_length/1`) and stored in each `inputs[n]` sub-map, but
there is no top-level summary scalar for it in `details_map`. The `@scalar_fields`
whitelist only covers top-level keys, so there is currently no way to reach
per-input scriptSig size from the DSL.

## Approach

Add `largest_script_sig_bytes` as a new top-level summary scalar in `details_map`,
following the same pattern as `largest_witness_item_bytes`. No new Gleam API calls
are needed — `script_sig_length` is already available on each extracted input map.

## Affected files

| File | Change |
|---|---|
| `lib/btc_tx_feed/tx_parser.ex` | Derive `largest_script_sig_bytes` from the extracted inputs list and merge it into `base` in `build_details/1` |
| `lib/btc_tx_feed/tx_retention_rules.ex` | Add `:largest_script_sig_bytes` to `@scalar_fields` MapSet |
| `data/retention_rules.exs` | Add corpus entry `B01` |

## Implementation steps

### 1. `lib/btc_tx_feed/tx_parser.ex`

In `build_details/1`, after `extract_inputs(inputs)` is called, compute:

```elixir
largest_script_sig_bytes =
  case extracted_inputs do
    [] -> 0
    inputs -> inputs |> Enum.map(& &1.script_sig_length) |> Enum.max()
  end
```

Add `largest_script_sig_bytes: largest_script_sig_bytes` to the `base` map
alongside the existing output script and witness summaries.

Bind the result of `extract_inputs/1` to a named variable (`extracted_inputs`)
so the summary derivation can reference it — currently the result is embedded
directly inside the `%{inputs: extract_inputs(inputs), ...}` literal.

### 2. `lib/btc_tx_feed/tx_retention_rules.ex`

Add `:largest_script_sig_bytes` to `@scalar_fields`:

```elixir
:largest_script_sig_bytes,
```

Place it alongside the other per-input summary scalars (near `inputs_with_witness_count`).

### 3. `data/retention_rules.exs`

Add a new entry using the `B` prefix (Bitcoin-specific / coinbase corpus):

```elixir
%{
  code: "B01",
  label: "Large coinbase scriptSig",
  limit: 3,
  rule: {:gte, :largest_script_sig_bytes, 80}
}
```

## Tests

- **`TxParser` tests** — assert `largest_script_sig_bytes` is present in the returned `details_map` for both legacy and segwit fixture transactions; verify the value equals the maximum `script_sig_length` across inputs.
- **`TxRetentionRules` tests** — add cases for `{:gte, :largest_script_sig_bytes, N}`: valid rule validation, match returns `true` when field meets threshold, match returns `false` when below threshold.

## Verification

```sh
mix test test/btc_tx_feed/tx_parser_test.exs
mix test test/btc_tx_feed/tx_retention_rules_test.exs
mix precommit
```

## Decisions and thresholds

- **Threshold: 80 bytes** — captures the upper ~20% of the 100-byte protocol ceiling. Adjustable via the `retention_rules.exs` data file without code changes.
- **Rule code: `B01`** — `B` prefix for the coinbase corpus category.
- **Field name: `largest_script_sig_bytes`** — mirrors `largest_witness_item_bytes` and `largest_script_pubkey_bytes` conventions.
- **No new predicate operator needed** — the existing `{:gte, field, value}` scalar operator is sufficient once the field is exposed.
