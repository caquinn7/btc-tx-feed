# Decode Policy Environment Variables

Make the `btc_tx` decode policy resource limits configurable via environment
variables, with the library's built-in defaults as fallbacks.

## Background

`BtcTxFeed.TxParser.parse/1` currently calls `:btc_tx.decode/1`, which applies
the library's hardcoded default policy. The policy controls how much work the
parser is allowed to do on a single transaction (input/output counts, script
sizes, witness limits). Exposing these as environment variables allows them to
be tuned on Fly.io via `fly secrets set` without a code change.

## Environment variables

| Variable | Default | Corresponds to |
|---|---|---|
| `DECODE_POLICY_MAX_VIN_COUNT` | `100000` | `max_vin_count` |
| `DECODE_POLICY_MAX_VOUT_COUNT` | `100000` | `max_vout_count` |
| `DECODE_POLICY_MAX_SCRIPT_SIZE` | `10000` | `max_script_size` |
| `DECODE_POLICY_WITNESS_ITEM_SIZE` | `10000` | witness `max_item_size` |
| `DECODE_POLICY_WITNESS_ITEMS_PER_INPUT` | `10000` | witness `max_items_per_input` |
| `DECODE_POLICY_WITNESS_STACK_PAYLOAD_BYTES` | `100000` | witness `max_stack_payload_bytes_per_input` |

Defaults match the `btc_tx` library defaults so that existing behaviour is
unchanged unless a variable is explicitly set.

## Changes

### 1. `config/runtime.exs`

Read the six env vars and store them as a flat keyword list under
`:btc_tx_feed, :decode_policy`. Apply to all environments so the values work
in dev and test too (useful for low-limit testing).
 
```elixir
config :btc_tx_feed, :decode_policy,
  max_vin_count:
    String.to_integer(System.get_env("DECODE_POLICY_MAX_VIN_COUNT", "100000")),
  max_vout_count:
    String.to_integer(System.get_env("DECODE_POLICY_MAX_VOUT_COUNT", "100000")),
  max_script_size:
    String.to_integer(System.get_env("DECODE_POLICY_MAX_SCRIPT_SIZE", "10000")),
  max_witness_item_size:
    String.to_integer(System.get_env("DECODE_POLICY_WITNESS_ITEM_SIZE", "10000")),
  max_witness_items_per_input:
    String.to_integer(System.get_env("DECODE_POLICY_WITNESS_ITEMS_PER_INPUT", "10000")),
  max_witness_stack_payload_bytes:
    String.to_integer(System.get_env("DECODE_POLICY_WITNESS_STACK_PAYLOAD_BYTES", "100000"))
```

Place this block outside the `if config_env() == :prod` guard so it applies in
all environments.

### 2. `lib/btc_tx_feed/tx_parser.ex`

Add a private `decode_policy/0` helper that reads application config and
constructs the Gleam record tuples expected by `decode_with_policy/2`:

```elixir
defp decode_policy do
  cfg = Application.get_env(:btc_tx_feed, :decode_policy, [])

  witness_policy =
    {:witness_policy,
     Keyword.get(cfg, :max_witness_item_size, 10_000),
     Keyword.get(cfg, :max_witness_items_per_input, 10_000),
     Keyword.get(cfg, :max_witness_stack_payload_bytes, 100_000)}

  {:decode_policy,
   Keyword.get(cfg, :max_vin_count, 100_000),
   Keyword.get(cfg, :max_vout_count, 100_000),
   Keyword.get(cfg, :max_script_size, 10_000),
   witness_policy}
end
```

Change `parse/1` to use `decode_with_policy/2`:

```elixir
def parse(raw_bytes) when is_binary(raw_bytes) do
  with {:ok, tx} <- :btc_tx.decode_with_policy(raw_bytes, decode_policy()) do
    {:ok, build_details(tx)}
  end
end
```

## Testing

Existing `TxParser` tests cover correct parsing behaviour — no structural
changes are needed there.

Add a focused test that sets lower policy limits via application config and
confirms `parse/1` returns `{:error, _}` for a transaction that would exceed
them. Use `Application.put_env/3` + `on_exit` (or the test config override
pattern) to isolate the override.

## Deployment

After merging:

```
fly secrets set DECODE_POLICY_MAX_VIN_COUNT=500 DECODE_POLICY_MAX_VOUT_COUNT=500
fly deploy
```

Values not explicitly set continue to use the library defaults.
