# btc_tx Public API

`btc_tx` is a Gleam library for parsing, inspecting, and validating Bitcoin
transactions. It supports both legacy and SegWit formats, exposes configurable
resource-limit policies for safe parsing of untrusted input, and uses phantom
types to distinguish unvalidated from consensus-validated transactions.

When used as an Erlang/OTP dependency from Elixir, every public function is
called as `:btc_tx.<function>(args)`. Gleam `Result` values appear in Elixir as
`{:ok, value}` / `{:error, reason}`. Gleam `BitArray` is an Elixir `binary()`.

---

## Table of Contents

1. [Decoding](#decoding)
2. [Transaction inspection](#transaction-inspection)
3. [Input inspection](#input-inspection)
4. [Output inspection](#output-inspection)
5. [Previous-output reference inspection](#previous-output-reference-inspection)
6. [Witness data](#witness-data)
7. [Script inspection](#script-inspection)
8. [Output script classification](#output-script-classification)
9. [Consensus validation](#consensus-validation)
10. [Serialization and transaction IDs](#serialization-and-transaction-ids)
11. [Decode policies](#decode-policies)
12. [Error types](#error-types)

---

## Decoding

### `decode(bytes :: binary()) :: {:ok, transaction()} | {:error, decode_error()}`

Parse a Bitcoin transaction from its binary wire encoding using the default
decode policy. Automatically detects legacy vs SegWit format. Returns an
`{:ok, transaction()}` that is marked as *unvalidated*.

```elixir
case :btc_tx.decode(raw_bytes) do
  {:ok, tx}                        -> tx
  {:error, {:parse_failed, _err}}  -> :error
  {:error, :hex_to_bytes_failed}   -> :error  # never occurs with binary input
end
```

### `decode_with_policy(bytes :: binary(), policy :: decode_policy()) :: {:ok, transaction()} | {:error, decode_error()}`

Same as `decode/1` but accepts a custom `decode_policy()` struct for
fine-grained resource limits. Useful when processing untrusted input.

### `decode_hex(hex :: String.t()) :: {:ok, transaction()} | {:error, decode_error()}`

Convenience wrapper: converts the hex string to bytes then calls `decode/1`.

- `{:error, :hex_to_bytes_failed}` — malformed hex (odd length or invalid chars).
- `{:error, {:parse_failed, _}}` — valid hex but invalid transaction bytes.

### `decode_hex_with_policy(hex :: String.t(), policy :: decode_policy()) :: {:ok, transaction()} | {:error, decode_error()}`

Same as `decode_hex/1` with a custom policy.

---

## Transaction inspection

All functions in this section accept any `transaction()`, both validated and
unvalidated, unless noted otherwise.

### `get_version(tx) :: integer()`

The transaction version number (1 = original format, 2 = BIP 68 relative
lock-time).

### `is_segwit(tx) :: boolean()`

`true` if the transaction uses the SegWit wire format (has witness stacks),
`false` if it is a legacy transaction.

### `get_inputs(tx) :: [txin()]`

The list of transaction inputs in serialization order.

### `get_outputs(tx) :: [txout()]`

The list of transaction outputs in serialization order.

### `get_lock_time(tx) :: integer()`

The lock-time field. Values `< 500_000_000` are block heights; values
`>= 500_000_000` are Unix timestamps; `0` means immediately valid.

### `get_witnesses(tx) :: {:ok, [witness_stack()]} | {:error, nil}`

Returns `{:ok, witnesses}` for SegWit transactions, `{:error, nil}` for legacy
transactions. The list is parallel to `get_inputs/1` — index N of the witness
list corresponds to input N.

### `has_coinbase_marker(tx) :: boolean()`

Structural check only. Returns `true` if any input has a null previous-output
(the coinbase marker). Does **not** verify consensus validity of the coinbase
transaction.

### `is_coinbase(validated_tx) :: boolean()`

Returns `true` if the **validated** transaction is a consensus-valid coinbase
transaction. Requires a `transaction(validated)` — use `validate_consensus/1`
first.

---

## Input inspection

### `get_input_prev_out(input :: txin()) :: prevout()`

The previous output being spent (or the coinbase marker for coinbase inputs).

### `get_input_sequence(input :: txin()) :: integer()`

The sequence number field of the input.

### `get_input_script_sig(input :: txin()) :: script_bytes(input_script)`

The raw scriptSig bytes for the input.

---

## Output inspection

### `get_output_value(output :: txout()) :: integer()`

The number of satoshis assigned to this output.

### `get_output_script_pubkey(output :: txout()) :: script_bytes(output_script)`

The raw scriptPubKey bytes (the locking script) for the output.

---

## Previous-output reference inspection

### `get_prev_out_txid(prevout :: prevout()) :: binary()`

32 bytes of the referenced transaction's txid in **little-endian** byte order
(as it appears on the wire). Returns all-zero bytes for coinbase inputs.

### `get_prev_out_vout(prevout :: prevout()) :: integer()`

Zero-based output index within the referenced transaction. Returns
`0xFFFFFFFF` for coinbase inputs.

---

## Witness data

### `get_witness_items(stack :: witness_stack()) :: [witness_item()]`

Items in a single input's witness stack, in serialization order.

### `get_witness_item_bytes(item :: witness_item()) :: binary()`

Raw bytes of a single witness item.

---

## Script inspection

### `get_raw_script_bytes(script :: script_bytes(k)) :: binary()`

The raw bytes of a scriptSig or scriptPubKey.

### `get_script_length(script :: script_bytes(k)) :: integer()`

Byte length of the script.

---

## Output script classification

### `classify_output_script(script :: script_bytes(output_script)) :: output_script_type()`

Identifies which standard Bitcoin script template a `scriptPubKey` matches.
Pass in the value from `get_output_script_pubkey/1`.

```elixir
script = :btc_tx.get_output_script_pubkey(output)
case :btc_tx.classify_output_script(script) do
  :p2_p_k_h                       -> :legacy_single_sig
  :p2_s_h                         -> :script_hash
  :p2_w_p_k_h                     -> :segwit_single_sig
  :p2_w_s_h                       -> :segwit_script_hash
  :p2_t_r                         -> :taproot
  :p2_p_k                         -> :pay_to_pubkey
  :multisig                       -> :bare_multisig
  :null_data                      -> :op_return
  {:unknown_witness, version: v}  -> {:future_witness_version, v}
  :non_standard                   -> :non_standard
end
```

### `output_script_type()` variants

| Variant | Description |
|---|---|
| `:p2_p_k` | Pay-to-public-key (compressed or uncompressed key + OP_CHECKSIG) |
| `:p2_p_k_h` | Pay-to-public-key-hash — most common legacy output |
| `:p2_s_h` | Pay-to-script-hash |
| `:p2_w_p_k_h` | SegWit v0 single-key spend |
| `:p2_w_s_h` | SegWit v0 script-hash spend |
| `:p2_t_r` | Taproot (SegWit v1) |
| `:multisig` | Bare m-of-n multisig (1 ≤ m ≤ n ≤ 3), Bitcoin Core standard |
| `:null_data` | OP_RETURN output, push-only after OP_RETURN, total ≤ 83 bytes |
| `{:unknown_witness, version: v}` | Future witness version (v is 1–16, excluding known ones) |
| `:non_standard` | Does not match any recognised template |

---

## Consensus validation

### `validate_consensus(tx :: transaction(unvalidated)) :: {:ok, transaction(validated)} | {:error, [validation_error()]}`

Checks a parsed transaction against Bitcoin consensus rules. Returns an `{:ok,
validated_tx}` on success or `{:error, errors}` where `errors` is a list
containing one or more `validation_error()` values (all detected errors are
collected, not just the first).

Rules checked:
- At least one input
- At least one output
- Every output value is in range: `0 <= value <= MAX_MONEY` (2,100,000,000,000,000 satoshis)
- Cumulative output value does not exceed `MAX_MONEY`
- Coinbase transactions have exactly one input
- Coinbase scriptSig is 2–100 bytes

Script execution and signature verification are **not** performed.

### `validation_error()` variants

| Variant | Meaning |
|---|---|
| `:no_inputs` | Transaction has no inputs |
| `:no_outputs` | Transaction has no outputs |
| `{:output_value_out_of_range, index: i, value: v}` | Output `i` has an out-of-range value |
| `{:total_output_value_out_of_range, index: i, total: t}` | Running output sum exceeded MAX_MONEY at output `i` |
| `:coinbase_with_multiple_inputs` | Coinbase transaction has more than one input |
| `:invalid_coinbase_script_sig_length` | Coinbase scriptSig length is not between 2 and 100 bytes |

---

## Serialization and transaction IDs

> **Note for Elixir callers:** Gleam enforces via phantom types that these
> functions only accept a validated transaction. Phantom types are erased at
> runtime, so this constraint is **not** enforced when calling from Elixir.
> Always call `validate_consensus/1` and unwrap the `{:ok, validated_tx}`
> result before passing a transaction to any function in this section.

### `compute_txid(tx :: transaction(validated)) :: binary()`

32-byte transaction identifier in **little-endian** byte order (as transmitted
on the Bitcoin network). Computed as `SHA256d(to_stripped_bytes(tx))`.

```elixir
{:ok, validated} = :btc_tx.validate_consensus(tx)
txid_le = :btc_tx.compute_txid(validated)
# To display as a conventional big-endian hex txid:
txid_be_hex = txid_le |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin() |> Base.encode16(case: :lower)
```

### `compute_wtxid(tx :: transaction(validated)) :: binary()`

32-byte witness transaction identifier in little-endian byte order.
Computed as `SHA256d(to_witness_bytes(tx))`. Equal to `compute_txid/1` for
legacy transactions.

### `to_stripped_bytes(tx :: transaction(validated)) :: binary()`

Serializes the transaction without any witness data (the "base" form used to
compute the txid). This is the `base_size` component in BIP 141 weight
calculations.

### `to_witness_bytes(tx :: transaction(validated)) :: binary()`

Serializes the transaction in its full wire form including SegWit marker, flag,
and witness stacks. This is the `total_size` component in BIP 141 weight
calculations.

BIP 141 weight and virtual size:

```
weight = base_size * 3 + total_size
vsize  = ceil(weight / 4)
```

where:
- `base_size = byte_size(:btc_tx.to_stripped_bytes(tx))`
- `total_size = byte_size(:btc_tx.to_witness_bytes(tx))`

---

## Decode policies

### `default_policy`

The policy applied by `decode/1` and `decode_hex/1`. A Gleam record with the
following field values:

| Field | Default | Description |
|---|---|---|
| `max_tx_size` | `400_000` | Maximum serialized transaction size in bytes; enforced before parsing begins |
| `max_vin_count` | `100_000` | Maximum number of inputs |
| `max_vout_count` | `100_000` | Maximum number of outputs |
| `max_script_size` | `10_000` | Maximum bytes for any single script (`scriptSig` or `scriptPubKey`) |
| `max_witness_items_per_input` | `10_000` | Maximum witness stack items per input |
| `max_witness_size_per_input` | `100_000` | Maximum total witness size in bytes per input |

### Constructing a custom policy from Elixir

`DecodePolicy` is a Gleam record, which compiles to a tagged Erlang tuple. To
construct one from Elixir:

```elixir
policy = {:decode_policy, 400_000, 100, 100, 1_000, 10_000, 10_000}
# {max_tx_size, max_vin_count, max_vout_count, max_script_size,
#  max_witness_items_per_input, max_witness_size_per_input}

{:ok, tx} = :btc_tx.decode_with_policy(raw_bytes, policy)
```

> **Note:** Field order in the tuple matches the order the fields are declared
> in the Gleam source. When in doubt, use the accessor values on `default_policy`
> as a reference.

---

## Error types

### `decode_error()`

| Variant | When |
|---|---|
| `:hex_to_bytes_failed` | Hex string is malformed (odd length or invalid characters) |
| `{:parse_failed, parse_error()}` | Bytes could not be parsed as a transaction |

### `parse_error()` — opaque

Accessed via the three accessor functions below.

#### `parse_error_offset(err) :: integer()`

Zero-based byte offset into the input where the error occurred.

#### `parse_error_kind(err) :: parse_error_kind()`

The specific error category.

#### `parse_error_ctx(err) :: [parse_context()]`

A context stack (outermost → innermost) showing where in the transaction
structure the error occurred, e.g.:

```
[:in_transaction, :in_inputs, {:at_input, 2}, {:at_field, :script_sig_length}]
```

### `parse_error_kind()` variants

| Variant | Meaning |
|---|---|
| `{:unexpected_eof, bytes_needed: n, remaining: r}` | Input ended too early |
| `{:non_minimal_compact_size, encoded: e, value: v}` | CompactSize used non-minimal encoding |
| `{:invalid_seg_wit_marker_flag, marker: m, flag: f}` | SegWit marker byte was 0x00 but flag was not 0x01 |
| `{:insufficient_bytes, claimed: c, remaining: r}` | Length field implies more bytes than available |
| `{:integer_out_of_range, string}` | 64-bit integer exceeds runtime range |
| `{:policy_limit_exceeded, value: v, max: m}` | A configurable policy limit was exceeded |
| `{:trailing_bytes, integer}` | Extra bytes remain after a complete transaction |

### `parse_context()` variants

| Variant | Meaning |
|---|---|
| `:in_transaction` | Top-level transaction structure |
| `:in_inputs` | Input vector |
| `{:at_input, i}` | Input at zero-based index `i` |
| `:in_outputs` | Output vector |
| `{:at_output, i}` | Output at zero-based index `i` |
| `{:at_witness_stack, i}` | Witness stack for input `i` |
| `{:at_witness_item, i}` | Witness item at index `i` |
| `{:at_field, field()}` | Specific named field (see below) |

### `field()` atoms

`:version`, `:lock_time`, `:segwit_discriminator`, `:segwit_marker`,
`:vin_count`, `:prev_tx_id`, `:vout`, `:script_sig`, `:script_sig_length`,
`:sequence`, `:vout_count`, `:value`, `:script_pub_key`, `:script_pub_key_length`,
`:witness_stack_length`, `:witness_item_length`, `:witness_stack_total_payload_bytes`
