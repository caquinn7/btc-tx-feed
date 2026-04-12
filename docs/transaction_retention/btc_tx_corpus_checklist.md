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

- [x] **C01 — Legacy simple**  
  _No witness, ~1 input, 2 outputs_

- [x] **C02 — Legacy multi-input**  
  _Multiple inputs, no witness_

- [x] **C03 — Legacy multi-output**  
  _Multiple outputs, no witness_

- [x] **C04 — SegWit simple (v0-like structure)**  
  _Witness present, simple structure (e.g., 1 input, small witness stacks)_

- [x] **C05 — Multi-input with multiple witnessed inputs**  
  _Multiple inputs, with multiple inputs carrying witness data_

- [x] **C06 — Single-witness-item input**  
  _At least one input with exactly one witness item_

- [ ] **C07 — Coinbase transaction (Manual / block-sourced; not expected from mempool feed)**  
  _Single input with coinbase marker_

---

# Witness Structure Variants

- [ ] **W01 — Multiple witness items (per input)**  
- [ ] **W02 — Mixed witness patterns across inputs**  
- [ ] **W03 — Large witness item**  

---

# Output Script Shapes (Parser-Visible)

- [x] **F01 — OP_RETURN output present**  
- [ ] **F02 — Multiple OP_RETURN outputs**  
- [ ] **F03 — Witness v0 output present (OP_0 + data)**  
- [ ] **F04 — Witness v1 output present (OP_1 + data)**  
- [ ] **F05 — Mixed output script types**  
- [ ] **F06 — Large scriptPubKey output**  

---

# Size / Complexity

- [x] **S01 — High input count**  
- [x] **S02 — High output count**  
- [ ] **S03 — Large transaction size (total serialized size >= 2,000 bytes)**  
- [ ] **S04 — Very small transaction (Total serialized size <= 150 bytes)**  
- [ ] **S05 — Many inputs + many outputs**  
- [x] **S06 — Witness-heavy transaction**  

---

# v1 Target (Start Here)

Focus on these first:

- [x] C01 Legacy simple  
- [x] C04 SegWit simple  
- [x] C06 Single-witness-item input present  
- [ ] C07 Coinbase  
- [x] F01 OP_RETURN  
- [x] C02 Multi-input  
- [x] C03 Multi-output  
- [x] C05 Multi-input with multiple witnessed inputs  
- [x] S01 High input count  
- [x] S02 High output count  
- [x] S06 Witness-heavy  

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

