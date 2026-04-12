# Plan: Transaction Retention Rule Foundations

## TL;DR

Prepare the app for a declarative transaction-retention DSL in two steps:

1. enrich the `details_map` returned by `BtcTxFeed.TxParser.parse/1` with rule-friendly derived fields
2. define a small, explicit, declarative DSL for matching parser-visible transaction characteristics

This plan **does not** cover wiring the DSL into `TxSampler`, persistence, or the LiveView flow yet.

---

## Goals

- Keep the rule system **safe, bounded, and maintainable**
- Avoid runtime code execution or arbitrary scripting for now
- Keep `btc_tx` focused on parsing/inspection primitives; do app-specific aggregation in `BtcTxFeed.TxParser`
- Make common structural rules easy to express, especially the checklist-driven cases in `docs/btc_tx_corpus_checklist.md`

## Non-goals

- No `Code.eval_string/3` or other runtime code execution
- No “script-like” syntax layer yet
- No integration plan yet for how rules affect the existing decode/stats/failure pipeline
- No UI/editor for creating rules yet

---

## Phase 1 – Enrich `TxParser.parse/1` details output

### Objective

Add a focused set of **derived, rule-friendly fields** to the `details_map` so the future DSL can stay small and avoid repeatedly traversing nested lists.

### Principle

Do **not** expand the public API of `btc_tx` for app-specific needs. Use the existing inspection functions documented in `docs/btc_tx_api.md` and compute the summaries inside `BtcTxFeed.TxParser`.

### Proposed additions to `details_map`

#### Output/script summaries

- `output_script_types` — ordered list of output script classifications
  - Example: `[:p2_p_k_h, :null_data, :p2_w_p_k_h]`
- `output_script_type_counts` — frequency map of output script types
  - Example: `%{:p2_p_k_h => 1, :null_data => 1, :p2_w_p_k_h => 1}`
- `has_op_return` — convenience boolean for common filtering
- `op_return_output_count` — count of `:null_data` outputs
- `has_non_standard_output` — convenience boolean for novelty-focused rules

#### Witness summaries

- `witness_item_counts_per_input` — list parallel to inputs
  - Example: `[2, 0, 1]`
- `witness_total_items` — total witness items across all inputs
- `witness_total_bytes` — total byte size of all witness items
- `largest_witness_item_bytes` — max byte size of a single witness item
- `inputs_with_witness_count` — how many inputs actually carry witness items

#### Optional convenience fields (nice to have, not mandatory)

- `size_bucket` — e.g. `:tiny | :small | :medium | :large`
- `input_count_bucket` — e.g. `:single | :few | :many`
- `output_count_bucket` — e.g. `:single | :few | :many`

> Recommendation: keep the buckets optional for v1. They are easy to add later and can also be expressed with range predicates in the DSL.

### Why these fields

They map directly to the corpus checklist and likely future retention use cases:

- `F01` / `F02` — OP_RETURN presence and multiplicity
- `F05` / `O02` — mixed or non-standard output script types
- `W02` / `W03` / `W04` / `W05` / `W06` — witness shape and size variants
- `S01` / `S02` / `S03` / `S06` — input/output/size complexity and witness heaviness

### Implementation notes

- Keep existing `inputs`, `outputs`, and `witnesses` fields intact for display/debugging
- Add private helper functions to compute the summaries from existing raw structures
- Prefer explicit names over deeply nested structures so the DSL evaluator can stay simple
- Avoid duplicating the same computation in multiple runtime rule checks

### Suggested tests for this phase

- parser test for a tx with `OP_RETURN` output → `has_op_return == true`
- parser test for a witness tx → witness counts/bytes fields are populated correctly
- parser test for legacy tx → witness summary fields are zero/empty in a predictable shape
- parser test for mixed output script types → `output_script_type_counts` matches expected frequencies

---

## Phase 2 – Define the declarative DSL

### Objective

Define a **small, explicit, closed-set DSL** for matching against the enriched `details_map`.

### Guiding constraints

- Rules must be plain data, not executable code
- Evaluation must be deterministic and bounded
- Supported predicates should fit on one screen and be easy to document
- The DSL should be expressive enough for the current checklist, without becoming a mini programming language

### Proposed rule representation

Represent rules as Elixir tuples (or maps later if persistence ergonomics demand it).

#### Boolean composition

- `{:all, [rule, ...]}` — every child rule must match
- `{:any, [rule, ...]}` — at least one child rule must match
- `{:not, rule}` — negate a child rule

#### Scalar comparisons

- `{:eq, field, value}`
- `{:neq, field, value}`
- `{:gt, field, value}`
- `{:gte, field, value}`
- `{:lt, field, value}`
- `{:lte, field, value}`
- `{:between, field, min, max}`
- `{:in, field, values}`

These should target stable top-level fields from `details_map`, such as:

- `:is_segwit`
- `:has_coinbase_marker`
- `:validated`
- `:input_count`
- `:output_count`
- `:base_size`
- `:total_size`
- `:weight`
- `:vsize`
- `:version`
- `:lock_time`
- the new witness/output summary fields

#### Domain-specific predicates

Keep a short approved set for cases that would otherwise be clumsy to express:

- `{:has_output_script_type, type}`
- `{:output_script_type_count_gte, type, n}`
- `{:has_any_output_script_type, [type, ...]}`
- `{:any_input_witness_items_eq, n}`
- `{:any_input_witness_items_gte, n}`
- `{:witness_total_items_gte, n}`
- `{:witness_total_bytes_gte, n}`
- `{:largest_witness_item_bytes_gte, n}`

> Recommendation: start with the smallest useful set and add more only when a real rule requires it.

### Example rules

#### Legacy multi-input tx

```elixir
{:all, [
  {:eq, :is_segwit, false},
  {:gte, :input_count, 3}
]}
```

#### SegWit tx with OP_RETURN output

```elixir
{:all, [
  {:eq, :is_segwit, true},
  {:has_output_script_type, :null_data}
]}
```

#### Witness-heavy or oddball tx

```elixir
{:any, [
  {:witness_total_bytes_gte, 500},
  {:eq, :has_non_standard_output, true}
]}
```

### Validation layer

Create a single module responsible for validation/evaluation, e.g.:

- `BtcTxFeed.TxRetentionRules.validate_rule/1`
- `BtcTxFeed.TxRetentionRules.match?/2`

Responsibilities:

- reject unknown operators
- reject unsupported fields
- reject malformed rule structure
- keep the evaluator total and predictable

### TDD expectations for this phase

Write focused evaluator tests before implementation:

- `:all` requires every predicate to pass
- `:any` passes if one predicate passes
- `:not` negates correctly
- scalar comparisons behave correctly on parser output
- script-type and witness-specific predicates behave correctly on real parsed fixture data
- invalid rules are rejected clearly

---

## Proposed file touch points

| File | Role |
|---|---|
| `lib/btc_tx_feed/tx_parser.ex` | Add derived summary fields |
| `lib/btc_tx_feed/tx_retention_rules.ex` | New evaluator/validator module |
| `test/btc_tx_feed/tx_parser_test.exs` | Parser field coverage |
| `test/btc_tx_feed/tx_retention_rules_test.exs` | DSL evaluation/validation coverage |
| `docs/btc_tx_corpus_checklist.md` | Coverage reference for rule/predicate needs |
| `docs/btc_tx_api.md` | Confirms the needed data can be derived today |

---

## Verification checklist

When the implementation happens, verify:

1. `TxParser.parse/1` returns the new fields for both legacy and SegWit transactions
2. The new summary fields are consistent with the existing `inputs`, `outputs`, and `witnesses` data
3. The DSL evaluator handles supported predicates and rejects unsupported ones
4. Example rules from the checklist (legacy multi-input, SegWit + OP_RETURN, witness-heavy) evaluate correctly
5. `mix test` and `mix precommit` pass

---

## Deferred for the next plan

The following are intentionally out of scope here and should be planned separately:

- where retention rules are stored/configured
- how the active rule set is loaded at runtime
- whether dropped transactions still affect stats/failure tracking
- how rules are applied inside the current `TxSampler` / pipeline flow
- whether a later “script-like” syntax should compile into this DSL
