# MVP 3 – Backpressure, Filtering, and Stability

## Purpose

MVP 3 introduces operational discipline into the live mempool feed.

The goal is no longer simply:

> receive txids and decode transactions

but instead:

> process a continuous stream safely under bounded resources while preserving responsiveness and observability.

This milestone is where the system begins behaving like a real streaming application rather than a prototype.

---

# Why this milestone exists

The mempool feed can produce bursts of transaction arrivals that exceed what a client can reasonably fetch and decode in real time, especially when relying on third-party APIs.

Using mempool.space:

- WebSocket provides a live stream of txids
- REST provides transaction data (`/tx/:txid`, `/tx/:txid/hex`, raw bytes)

This creates an immediate architectural constraint:

> txids arrive faster than full transaction fetch + decode can safely occur if every transaction is processed.

So MVP 3 focuses on controlling load rather than maximizing throughput.

---

# Core problem

A txid alone does not contain enough information for meaningful filtering.

To answer questions like:

- Is this Taproot?
- Does it have witness data?
- How many outputs?
- What script types are present?

you must fetch transaction data first.

That means:

> deep filtering requires decode.

But decoding every transaction fetched from a third-party API is not sustainable at scale.

---

# Practical filtering strategies

## Strategy A – Metadata-first filtering

Use cheap transaction metadata before full decode.

### Flow

1. Receive txid from WebSocket
2. Fetch transaction summary JSON (`/tx/:txid`)
3. Apply lightweight filters
4. Fetch hex/raw only for selected transactions
5. Decode selected transactions

### Suitable metadata filters

- minimum fee rate
- minimum vsize
- minimum total fee
- minimum output value (if available)

### Not possible without decode

- script classification
- witness inspection
- stack structure
- input/output script pattern analysis

This means MVP 3 filtering should be explicitly defined as:

> metadata filtering, not structural transaction filtering.

---

## Strategy B – Controlled sampling

Instead of attempting full-rate coverage, decode at a fixed sustainable rate.

### Flow

1. Ingest all txids
2. Push into bounded queue
3. Worker pool fetches at controlled rate
4. Decode only what workers reach

This gives:

- stable parser burn-in
- predictable resource usage
- useful transaction diversity

This is often the best option when the goal is battle-testing the parser.

---

## Strategy C – Full decode only after running your own node

Full mempool structural filtering only becomes realistic when transaction data is local.

### Why

A local Bitcoin node removes:

- third-party rate limits
- extra HTTP round trips
- external API dependency

### Future upgrade path

Run Bitcoin Core and subscribe to:

- ZMQ `rawtx`
- local mempool queries

Then every transaction can be decoded immediately.

This is naturally a later milestone.

---

# MVP 3 success criteria

MVP 3 succeeds if the system can:

- remain stable under bursty transaction arrival
- avoid unbounded memory growth
- tolerate API latency
- tolerate API failure
- preserve UI responsiveness
- expose internal throughput clearly

---

# Required system controls

## Bounded queue

Queue size must have a hard limit.

Example:

- queue size = 5000 txids

When full:

- drop oldest, or
- drop newest

Policy must be explicit.

---

## Worker pool

A fixed number of concurrent fetch/decode workers.

Example:

- 4–8 workers

This prevents accidental fan-out overload.

---

## Rate limiting

Outbound HTTP must be globally throttled.

Example:

- token bucket
- max requests/sec

Without this, bursts can trigger:

- HTTP 429
- degraded latency
- unstable retries

---

## Decode isolation

Decode failures must never stop the stream.

Every transaction decode should be isolated:

- success → publish result
- failure → record + continue

---

## Observability

You should always know:

- txids received/sec
- txids dropped/sec
- summary fetch latency
- decode latency
- decode failures
- queue depth

Without this, backpressure tuning becomes guesswork.

---

# Recommended MVP 3 pipeline

```text
WebSocket txids
    ↓
Bounded queue
    ↓
Worker pool
    ↓
Stage A: summary fetch
    ↓
Metadata filter
    ↓
Stage B: hex/raw fetch
    ↓
Gleam decode
    ↓
Publish to UI