defmodule BtcTxFeed.DecodePolicy do
  @moduledoc """
  Reads the active `btc_tx` decode policy from application config and exposes
  it in two forms:

  - `get/0` — a plain map of the resolved values, suitable for display.
  - `to_btc_tx_policy/0` — the Gleam record tuple expected by
    `:btc_tx.decode_with_policy/2`.

  Default values match the `btc_tx` library's built-in defaults and are also
  used as fallbacks in `config/runtime.exs`.
  """

  @defaults %{
    max_tx_size: 400_000,
    max_vin_count: 100_000,
    max_vout_count: 100_000,
    max_script_size: 10_000,
    max_witness_items_per_input: :none,
    max_witness_size_per_input: :none
  }

  @doc "Returns the active policy as a map, merging app config over the defaults."
  def get do
    cfg = Application.get_env(:btc_tx_feed, :decode_policy, [])
    Map.merge(@defaults, Map.new(cfg))
  end

  @doc "Returns the Gleam record tuple for use with `:btc_tx.decode_with_policy/2`."
  def to_btc_tx_policy do
    policy = get()

    {
      :decode_policy,
      policy.max_tx_size,
      policy.max_vin_count,
      policy.max_vout_count,
      policy.max_script_size,
      policy.max_witness_items_per_input,
      policy.max_witness_size_per_input
    }
  end
end
