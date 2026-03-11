# Track Mempool Txids

## WebSocket Endpoint

`wss://mempool.space/api/v1/ws`

---

## Description

Low-bandwidth substitute to the `track-mempool` command: subscribe to new mempool events, such as new transactions entering the mempool, but only transaction IDs are returned to save bandwidth.

Available fields:

* `added`
* `removed`
* `mined`
* `replaced`

---

## Subscription Payload

```json
{ "track-mempool-txids": true }
```

---

## Response

```json
{
  "mempool-txids": {
    "sequence": 79919,
    "added": [
      "4bbb648ab194aaaf9188bccc6efcdcbb59c8485115a7384972c8287782206a0f",
      "f7883f3784829d1e741e696bdceec488eeb53fe0b69b0eca574ac9f2e7e8e117",
      "784e8e3b182c29798660bf42befb5c6479148c7d90c0d6eea032b89418e7cc3b",
      "d3920a7be05269d859bd89b08a6546dc6d6dd523dbc5f7b62b9c0c5eedc43292",
      "de6078d584cb5f4a27c3f0bb3d8bbb16b3d5f8303237391f390d0ee9e84d0099",
      "39fcbd6e0ec0ad49405f19c72bb033f578147181b77dbe47044f80b0b7604ab5",
      "47ed060004fab3fb5fa4885008aa2cadbe3335655f1303231abfe89b4b0c9bd9"
    ],
    "removed": [],
    "mined": [],
    "replaced": []
  }
}
```

---

## Notes

* This stream is designed to minimize bandwidth by returning only transaction IDs rather than full transaction objects.
* A single message may contain multiple txids in the `added` array.
* The `sequence` field represents mempool event ordering and can be used to detect missed updates.
* Full transaction data requires additional REST API calls using each txid.

---

## REST Endpoint

`GET https://mempool.space/api/tx/:txid/raw`

### Description

Returns a transaction as binary data.

### Example

```bash
curl -sSL "https://mempool.space/api/tx/15e10745f15593a899cef391191bdd3d7c12412cc4696b7bcb669d0feadc8521/raw"
```
