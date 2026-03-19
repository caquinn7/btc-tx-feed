# Plan: TxStats persistence across restarts

## Goal

Persist ETS analytics counters to disk on graceful shutdown and reload them on
startup, so stats survive application restarts. Periodic flushing bounds data
loss on hard crashes.

---

## Approach

Use Erlang term serialisation (`:erlang.term_to_binary/1` / `:erlang.binary_to_term/1`)
to snapshot the raw ETS entry list to a `.bin` file. This handles the mixed-type
keys (atoms, tuples like `{:vsize_bucket, :tiny}`) without any schema or encoding
complexity. No new dependencies required.

Atomic writes via a `.tmp` → rename pattern prevent corrupt snapshots from a
mid-write crash.

---

## Changes

### 1. Config: snapshot path

Add a config key so the file location is environment-aware.

**`config/config.exs`** (dev/test default — project root):
```elixir
config :btc_tx_feed, :tx_stats_snapshot_path,
  Path.expand("../tx_stats_snapshot.bin", __DIR__)
```

**`config/runtime.exs`** (inside the `config_env() == :prod` block):
```elixir
config :btc_tx_feed, :tx_stats_snapshot_path,
  System.get_env("TX_STATS_SNAPSHOT_PATH", "/data/tx_stats_snapshot.bin")
```

This keeps the snapshot alongside the SQLite DB on the Fly.io `/data/` volume,
which is already a persisted mount.

---

### 2. `TxStats` GenServer — three additions

All changes are confined to `lib/btc_tx_feed/tx_stats.ex`.

#### a) Trap exits so `terminate/2` is called on graceful shutdown

```elixir
@impl true
def init(_) do
  Process.flag(:trap_exit, true)   # <-- add this

  :ets.new(@table, [
    :named_table, :public, :set,
    read_concurrency: true,
    write_concurrency: true
  ])

  load_snapshot()                  # <-- add this
  schedule_flush()                 # <-- add this

  {:ok, nil}
end
```

#### b) Periodic flush

The interval is environment-aware — short in dev for easy testing, full 5 minutes
in prod:

```elixir
@flush_interval if Mix.env() == :prod, do: :timer.minutes(5), else: :timer.seconds(30)

defp schedule_flush do
  Process.send_after(self(), :flush, @flush_interval)
end

@impl true
def handle_info(:flush, state) do
  persist_snapshot()
  schedule_flush()
  {:noreply, state}
end
```

#### c) Persist on graceful shutdown

```elixir
@impl true
def terminate(reason, _state) do
  require Logger
  Logger.info("TxStats: terminate/2 called (#{inspect(reason)}), flushing snapshot")
  persist_snapshot()
end
```

#### d) Private helpers

```elixir
defp snapshot_path do
  Application.get_env(:btc_tx_feed, :tx_stats_snapshot_path)
end

defp load_snapshot do
  case snapshot_path() do
    nil ->
      :ok

    path ->
      case File.read(path) do
        {:ok, binary} ->
          entries = :erlang.binary_to_term(binary)
          :ets.insert(@table, entries)

        {:error, :enoent} ->
          :ok

        {:error, reason} ->
          require Logger
          Logger.warning("TxStats: could not read snapshot #{path}: #{inspect(reason)}")
      end
  end
end
```

Note: `:erlang.binary_to_term/2` is called **without** the `[:safe]` flag. The
`[:safe]` flag rejects atoms not already in the VM's atom table — which causes a
crash on a fresh boot before any of the stats-related atoms have been loaded.
Since the snapshot file is written by the app itself to a path we configure,
there is no untrusted input concern here.

---

### 3. `Application` — OS signal handler

Add a `setup_signal_handlers/0` call in `BtcTxFeed.Application.start/2` to
ensure SIGTERM (sent by Fly.io on `fly machine stop` / deploy) triggers a full
OTP shutdown, causing `terminate/2` to run:

```elixir
defp setup_signal_handlers do
  # SIGINT (Ctrl-C) is managed by the Erlang VM break handler and cannot be
  # intercepted here — rely on the periodic flush for dev restarts.
  System.trap_signal(:sigterm, :graceful_shutdown, fn ->
    System.stop(0)
    :ok
  end)
end
```

Called as the first thing in `start/2`:

```elixir
def start(_type, _args) do
  setup_signal_handlers()
  maybe_migrate()
  ...
end
```

defp persist_snapshot do
  entries = :ets.tab2list(@table)
  binary  = :erlang.term_to_binary(entries)
  path    = snapshot_path()
  tmp     = path <> ".tmp"

  with :ok <- File.write(tmp, binary),
       :ok <- :file.rename(tmp, path) do
    :ok
  else
    {:error, reason} ->
      require Logger
      Logger.error("TxStats: snapshot write failed: #{inspect(reason)}")
  end
end
```

---

## File write safety

| Concern | Mitigation |
|---|---|
| Mid-write crash corrupts snapshot | Write to `.tmp`, rename atomically |
| Hard kill / OOM / SIGKILL skips `terminate/2` | Periodic flush (30 s dev / 5 min prod) caps data loss |
| Ctrl-C in `mix phx.server` (dev) skips `terminate/2` | Periodic flush handles this — Erlang VM break handler is not interceptable |
| Snapshot has stale data after a clean wipe | Delete the file manually; counters start from zero |
| `binary_to_term` on atoms not yet loaded | Call without `[:safe]` — file is written by the app to a configured local path, not external input |

---

## What is NOT in scope

- No SQLite migration or Ecto schema — serialised binary is sufficient for flat
  counters and avoids schema evolution complexity.
- No reset/wipe UI or HTTP endpoint — out of scope for this change.
- No test environment persistence — snapshot path is set to `nil` in `test.exs`,
  so persistence is silently skipped in tests.

---

## Rollout

1. Add config keys (`config/config.exs` + `config/runtime.exs` + `nil` in `config/test.exs`)
2. Update `TxStats.init/1` — trap exits, load snapshot, schedule flush
3. Add `handle_info(:flush, ...)` and `terminate/2`
4. Add private helpers `load_snapshot/0`, `persist_snapshot/0`, `snapshot_path/0`
5. Add `setup_signal_handlers/0` to `Application`
6. Add `tx_stats_snapshot.bin` and `.tmp` variant to `.gitignore`
7. Run `mix precommit`
8. Deploy — first start will create the snapshot file; subsequent restarts will
   warm-start from it

---

## Acceptance criteria

- In dev: after accumulating stats, wait >30 s for the periodic flush, then
  Ctrl-C and restart — counters are non-zero and match pre-shutdown values.
  To guarantee stats survive a restart without waiting for the flush, run via
  `iex -S mix phx.server` and quit with `:init.stop()` — this triggers the full
  OTP shutdown sequence and `terminate/2` flushes immediately.
- In prod: `fly machine stop` sends SIGTERM → `terminate/2` log line visible →
  restart resumes from pre-shutdown values without waiting for a flush.
- Deleting the snapshot file and restarting starts from zero without errors.
- A simulated mid-write crash (e.g. truncated `.tmp`) leaves the previous good
  snapshot intact and the app restarts cleanly with it.
