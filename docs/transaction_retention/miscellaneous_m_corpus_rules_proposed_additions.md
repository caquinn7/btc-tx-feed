# Miscellaneous (M) Corpus Rules — Proposed Additions

This document defines additional **M-category (Miscellaneous)** rules to capture structurally unusual but parser-visible transaction patterns.

These rules are:
- objective (based on `details_map` only)
- reproducible via DSL predicates
- complementary to existing C / F / S categories (not redundant with them)

Each rule is designed to represent a **distinct structural signal**, not just “weirdness” in a vague sense.

---

## Existing Rules (Reference)

```elixir
%{
  code: "M01",
  label: "Non-standard output present",
  limit: 1,
  rule: {:eq, :has_non_standard_output, true}
},
%{
  code: "M02",
  label: "Quantity of :null_data occurrences across outputs",
  limit: 1,
  rule: {:output_script_type_count_gte, :null_data, 2}
}
```

---

# Proposed Additions

## OP_RETURN + high output count

### Rule
```elixir
{:all, [
  {:eq, :has_op_return, true},
  {:gte, :output_count, 10}
]}
```

### Explanation
Captures transactions that:
- include OP_RETURN metadata
- also distribute funds across many outputs

This is structurally more interesting than a simple OP_RETURN + change pattern.

### Why it matters
- Combines **data embedding + distribution behavior**
- Often seen in batching, inscriptions, or custom protocols

---

## Small structure + large witness item

### Rule
```elixir
{:all, [
  {:lte, :input_count, 2},
  {:lte, :output_count, 3},
  {:largest_witness_item_bytes_gte, 500}
]}
```

### Explanation
A transaction that *looks simple* structurally but contains a **large witness payload**.

### Why it matters
- Highlights contrast between:
  - small visible structure
  - large hidden data payload
- Good at surfacing unusual witness usage patterns

---

## SegWit + multiple OP_RETURN outputs

### Rule
```elixir
{:all, [
  {:eq, :is_segwit, true},
  {:output_script_type_count_gte, :null_data, 2}
]}
```

### Explanation
Combines:
- SegWit transaction structure
- multiple OP_RETURN outputs

### Why it matters
- Narrows M02 into a more specific structural pattern
- Useful for detecting multi-metadata SegWit transactions

---

## Single-witness-item input + high output count

### Rule
```elixir
{:all, [
  {:eq, :is_segwit, true},
  {:any_input_witness_items_eq, 1},
  {:gte, :output_count, 10}
]}
```

### Explanation
Captures transactions where:
- at least one input has exactly one witness item
- but the transaction distributes to many outputs

### Why it matters
- Mixes a **minimal witness structure** with **complex output structure**
- Often not typical of standard wallet behavior

---

## High script diversity + non-standard output

### Rule
```elixir
{:all, [
  {:eq, :has_non_standard_output, true},
  {:distinct_output_script_types_gte, 2}
]}
```

### Explanation
Transaction includes:
- at least one non-standard output
- plus multiple script types overall

### Why it matters
- Strong signal of unusual or experimental construction
- More selective than M01 alone

---

## Large witness payload (upper-range signal)

### Rule
```elixir
{:witness_total_bytes_gte, 2000}
```

### Explanation
A stricter version of S06-like behavior, but used here to capture **extreme witness usage**.

### Why it matters
- Distinguishes between:
  - moderately large witness data
  - truly heavy payload transactions

---

## High output diversity + high output count

### Rule
```elixir
{:all, [
  {:distinct_output_script_types_gte, 3},
  {:gte, :output_count, 10}
]}
```

### Explanation
Transaction has:
- many outputs
- many different script types

### Why it matters
- Indicates complex or highly customized output construction
- Much rarer than either condition alone

---

# Design Notes

## 1. Avoid redundancy with S-codes

M-rules should avoid being purely:
- “large” (S-codes)
- “many inputs/outputs” (S01/S02)

Instead, they should emphasize:
> **unusual combinations of features**

---

## 2. Prefer combinations over magnitude

Better:
```elixir
{:all, [{:eq, :has_op_return, true}, {:gte, :output_count, 10}]}
```

Worse (belongs in S-category):
```elixir
{:gte, :output_count, 50}
```

---

## 3. Keep rules explainable

Each rule should answer:
> “What specific structural signal does this represent?”

If the answer is vague (“just weird”), the rule should be refined.

---

## 4. Use limit = 1 intentionally

Using `limit: 1` for M-codes is a strong choice because:
- these are **representative anomalies**, not distributions
- one good example is often sufficient for fuzzing seed diversity

---

# Suggested Final Set (M01–M10)

```elixir
M01 — non-standard output present
M02 — multiple OP_RETURN outputs
M03 — OP_RETURN + high output count
M04 — small structure + large witness item
M05 — SegWit + multiple OP_RETURN outputs
M06 — single-witness-item input + high output count
M07 — non-standard + multiple script types
M08 — large witness payload (high threshold)
M09 — high output diversity + high output count
```

---

# Summary

The M-category is now:
- **well-scoped** (not vague “oddball”)
- **DSL-expressible**
- **structurally meaningful**

It complements:
- C → core shapes
- F → output script features
- S → size/scale

by capturing:
> **unusual combinations and structural edge cases**

