# btc_tx Corpus Checklist (Parser-Visible, Structural)

## Purpose

This corpus supports:

- fuzzing seed inputs  
- regression testing  
- performance benchmarking  
- parser validation (structure-only)  
- preserving real-world transaction diversity  

Goal: **maximize structural coverage observable from raw transaction bytes**

---

## Status Legend

- [ ] TODO  
- [x] HAVE  
- [~] EXPAND (have at least one, want more)  

---

# Core Structural Shapes (Parser-Visible)

- [ ] **C01 — Legacy simple**  
  _No witness, ~1 input, 2 outputs_

- [ ] **C02 — Legacy multi-input**  
  _Multiple inputs, no witness_

- [ ] **C03 — Legacy multi-output**  
  _Multiple outputs, no witness_

- [ ] **C04 — SegWit simple (v0-like structure)**  
  _Witness present, simple structure (e.g., 1 input, small witness stacks)_

- [ ] **C05 — SegWit multi-input**  
  _Multiple inputs, each with witness_

- [ ] **C06 — SegWit single-witness-item input**  
  _At least one input with exactly one witness item_

- [ ] **C07 — Coinbase transaction**  
  _Single input with coinbase marker_

---

# Witness Structure Variants

- [ ] **W01 — No witness (legacy)**  
- [ ] **W02 — Single witness item (per input)**  
- [ ] **W03 — Multiple witness items (per input)**  
- [ ] **W04 — Mixed witness patterns across inputs**  
- [ ] **W05 — Large witness item**  
- [ ] **W06 — Large total witness payload**

---

# Output Script Shapes (Parser-Visible)

- [ ] **F01 — OP_RETURN output present**  
- [ ] **F02 — Multiple OP_RETURN outputs**  
- [ ] **F03 — Witness v0 output present (OP_0 + data)**  
- [ ] **F04 — Witness v1 output present (OP_1 + data)**  
- [ ] **F05 — Mixed output script types**  
- [ ] **F06 — Large scriptPubKey output**  

---

# Size / Complexity

- [ ] **S01 — High input count**  
- [ ] **S02 — High output count**  
- [ ] **S03 — Large transaction size**  
- [ ] **S04 — Very small valid transaction**  
- [ ] **S05 — Many inputs + many outputs**  
- [ ] **S06 — Witness-heavy transaction**  

---

# Oddball / Regression / Novelty

- [ ] **O01 — Weird real-world transaction**  
- [ ] **O02 — Unknown / unclassified script pattern**  
- [ ] **O03 — Bug-triggering transaction (regression)**  
- [ ] **O04 — Structurally surprising but valid transaction**  

---

# v1 Target (Start Here)

Focus on these first:

- [ ] C01 Legacy simple  
- [ ] C04 SegWit simple  
- [ ] C06 Single witness item input present.  
- [ ] C07 Coinbase  
- [ ] F01 OP_RETURN  
- [ ] C02 Multi-input  
- [ ] C03 Multi-output  
- [ ] C05 SegWit multi-input with multiple witnessed inputs  
- [ ] S01 High input count  
- [ ] S02 High output count  
- [ ] S06 Witness-heavy  
- [ ] O01 Oddball  

---

# Suggested Buckets (Parser-Visible)

## Input Count
- [ ] 1  
- [ ] 2–5  
- [ ] 6–20  
- [ ] >20  

## Output Count
- [ ] 1  
- [ ] 2–5  
- [ ] 6–20  
- [ ] >20  

## Transaction Size (bytes)
- [ ] <150  
- [ ] 150–500  
- [ ] 500–2000  
- [ ] >2000  

## Witness Size
- [ ] none  
- [ ] small  
- [ ] medium  
- [ ] large  

---

# Metadata to Store Per Transaction

For each captured transaction, store:

- [ ] txid  
- [ ] raw bytes / hex  
- [ ] slot_id  
- [ ] source (manual / app / regression)  
- [ ] captured_at  
- [ ] input_count  
- [ ] output_count  
- [ ] tx_size  
- [ ] weight  
- [ ] vsize  
- [ ] is_segwit  
- [ ] witness_item_counts_per_input  
- [ ] output_script_types (derived from scriptPubKey only)  
- [ ] notes (why this transaction was captured)
