# Live Mempool App – MVP Feasibility with Third-Party API Constraints

## Context

The current external data source provides:

- A WebSocket feed of newly added mempool txids
- A REST endpoint that returns:
  - transaction hex
  - or raw bytes
- Additional summary endpoints (metadata) may be available, but are still subject to rate limits

This means:

- Real-time feed gives identifiers only
- Deep transaction inspection requires additional per-tx requests
- Full mempool decoding through third-party APIs is not realistic at scale

---

## MVP 1 – Fully Feasible

### Approach

- Subscribe to live txids via WebSocket
- Display a rolling live list in LiveView
- Fetch raw tx data only when a user clicks a transaction

### Why This Works

- Very low API pressure
- No need for worker pools yet
- Ideal for learning:
  - Phoenix
  - LiveView
  - PubSub
- Immediate real-world testing for `btc_tx`

### Practical Outcome

MVP 1 remains unchanged and is a strong first milestone.

---

## MVP 2 – Still Feasible

### Additions

- Compute and display:
  - `txid`
  - `wtxid`
  - size
  - weight
  - vsize

### Important Constraint

Fee calculation usually requires previous output values:

fee = sum(prevouts) - sum(outputs)

Raw transaction bytes alone do not provide prevout values.

### Practical Solution

For MVP 2:

- Use fee metadata from third-party summary APIs when available
- Do not require local fee computation yet

### Practical Outcome

MVP 2 remains viable with slight scope discipline.

---

## MVP 3 – Feasible, But Scope Must Be Refined

## Original Challenge

Deep filtering requires decoded transaction contents.

But:

- WebSocket provides only txids
- Fetching hex/raw for every tx is expensive
- Third-party APIs likely impose rate limits

---

## Realistic MVP 3 Strategy

### Option A – Metadata-first filtering

Use lightweight summary endpoints first:

- fee
- vsize
- value

Then only fetch raw tx bytes for transactions that pass filters.

### Option B – Sampled decoding

Maintain a bounded queue and decode only a controlled subset:

- fixed worker pool
- fixed request rate
- backpressure handling

This still battle-tests `btc_tx` effectively.

---

## What MVP 3 Should Actually Focus On

- bounded ingestion queue
- worker pool
- outbound request rate limiting
- drop strategy under pressure
- parse failure tracking
- throughput metrics

---

## What MVP 3 Should Not Promise Yet

Not realistic with third-party APIs:

- decode every mempool transaction
- deep filtering across full mempool in real time

---

## Natural Future Evolution

## MVP 4 – Run Your Own Bitcoin Node

Once using Bitcoin Core + local feed:

- no third-party rate limits
- full raw transaction access
- full-rate decoding becomes realistic
- deep filtering becomes practical

---

## Final Roadmap

### Before MVP 1 – `btc_tx` Readiness

- Ensure `decode` and `decode_hex` remain stable on real-world transactions
- Improve parse error rendering so failures are easy to inspect in LiveView
- Keep transaction inspection APIs simple for UI use (`get_inputs`, `get_outputs`, etc.)

### MVP 1

**Goal:** Establish a minimal end-to-end live mempool viewer.

- Subscribe to live txids
- Render a rolling transaction list in LiveView
- Fetch and decode only selected transactions
- Display parsed transaction details
- Surface parse failures clearly

### Before MVP 2 – `btc_tx` Readiness

- Implement canonical serialization
- Add `txid` and `wtxid` computation
- Add lightweight transaction summary helpers for UI consumption

### MVP 2

**Goal:** Turn selected transaction inspection into protocol-aware analysis.

- Display `txid`, `wtxid`
- Display size / weight / vsize
- Add script classification for common output types
- Use third-party fee metadata where available

### Before MVP 3 – `btc_tx` Readiness

- Add structured parse debug output suitable for logging
- Add exportable failing vectors for regression tests
- Seed tests with real-world golden vectors

### MVP 3

**Goal:** Introduce bounded throughput and operational stability.

- Add bounded ingestion queue
- Add worker pool for outbound fetches
- Add request rate limiting
- Add metadata-first or sampled filtering
- Track throughput and parse failures

### MVP 4

**Goal:** Remove third-party bottlenecks.

- Run a local Bitcoin node
- Consume raw transaction feed locally
- Enable full-rate decoding and deep filtering

