defmodule BtcTxFeed.RetentionConfig do
  @moduledoc """
  Accessor for the retention corpus entries configured at startup.

  Entries are read from the application environment on each call. In normal
  operation the environment is populated once by `runtime.exs` and not mutated
  afterwards, so the entries are effectively fixed for the lifetime of the app.
  Use `matching_entries/1` to find all corpus entries whose rule matches a
  parsed transaction `details_map`.

  Returns an empty list for all transactions when no entries are configured.
  """

  alias BtcTxFeed.TxRetentionRules

  @doc """
  Returns the list of corpus entries currently in the application env.
  """
  def entries do
    Application.get_env(:btc_tx_feed, :retention_rules, [])
  end

  @doc """
  Returns all configured corpus entries whose rule matches `details`.
  Returns an empty list when no entries are configured or none match.
  Entries are returned in declaration order.
  """
  def matching_entries(details) do
    Enum.filter(entries(), fn %{rule: rule} ->
      TxRetentionRules.match?(details, rule)
    end)
  end
end
