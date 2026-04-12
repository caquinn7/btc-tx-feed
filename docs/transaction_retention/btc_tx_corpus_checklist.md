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
- [r] RULE DEFINED
- [x] HAVE  
- [~] EXPAND (have at least one, want more)  

---

# Core Structural Shapes (Parser-Visible)

- [r] **C01 — Legacy simple**  
  _No witness, ~1 input, 2 outputs_

- [r] **C02 — Legacy multi-input**  
  _Multiple inputs, no witness_

- [r] **C03 — Legacy multi-output**  
  _Multiple outputs, no witness_

- [r] **C04 — SegWit simple (v0-like structure)**  
  _Witness present, simple structure (e.g., 1 input, small witness stacks)_

- [r] **C05 — Multi-input with multiple witnessed inputs**  
  _Multiple inputs, with multiple inputs carrying witness data_

- [r] **C06 — Single-witness-item input**  
  _At least one input with exactly one witness item_

- [ ] **C07 — Coinbase transaction (Manual / block-sourced; not expected from mempool feed)**  
  _Single input with coinbase marker_

---

# Witness Structure Variants

- [r] **W01 — At least one input with multiple witness items**  
- [ ] **W02 — Mixed witness patterns across inputs**  
- [r] **W03 — Large witness item (largest_witness_item_bytes >= 200)**  

---

# Output Script Shapes (Parser-Visible)

- [r] **F01 — OP_RETURN output present**  
- [r] **F02 — Multiple OP_RETURN outputs**  
- [r] **F03 — Witness v0 output present (OP_0 + data)**  
- [r] **F04 — Witness v1 output present (OP_1 + data)**   
- [r] **F05 — Mixed output script types**  
- [r] **F06 — Large scriptPubKey output**  

---

# Size / Complexity

- [r] **S01 — High input count**  
- [r] **S02 — High output count**  
- [r] **S03 — Large transaction size (total serialized size >= 2,000 bytes)**  
- [ ] **S04 — Very small transaction (Total serialized size <= 150 bytes)**  
- [r] **S05 — Many inputs + many outputs**  
- [r] **S06 — Witness-heavy transaction**  

---

# v1 Target (Start Here)

Focus on these first:

- [ ] C01 Legacy simple  
- [ ] C04 SegWit simple  
- [ ] C06 Single-witness-item input present  
- [ ] C07 Coinbase  
- [ ] F01 OP_RETURN  
- [ ] C02 Multi-input  
- [ ] C03 Multi-output  
- [ ] C05 Multi-input with multiple witnessed inputs  
- [ ] S01 High input count  
- [ ] S02 High output count  
- [ ] S06 Witness-heavy  

---

# Suggested Buckets (Parser-Visible)
_To be updated based on actual captured transactions. Buckets won't necessarily determine what rules are defined._

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

