defmodule BtcTxFeed.RetentionConfig do
  @moduledoc """
  Accessor for the retention rules configured at startup.

  Rules are read from the application environment on each call. In normal
  operation the environment is populated once by `runtime.exs` and not mutated
  afterwards, so the rules are effectively fixed for the lifetime of the app.
  Use `any_match?/1` to test a parsed transaction `details_map` against the
  active rule set.

  Returns `false` for all transactions when no rules are configured.
  """

  alias BtcTxFeed.TxRetentionRules

  @doc """
  Returns the list of retention rules currently in the application env.
  """
  def rules do
    Application.get_env(:btc_tx_feed, :retention_rules, [])
  end

  @doc """
  Returns `true` if `details` matches at least one configured retention rule.
  Returns `false` when no rules are configured.
  """
  def any_match?(details) do
    Enum.any?(rules(), &TxRetentionRules.match?(details, &1))
  end
end
