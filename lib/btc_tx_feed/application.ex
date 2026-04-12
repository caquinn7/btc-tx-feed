defmodule BtcTxFeed.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias BtcTxFeed.MempoolSocket

  use Application

  @impl true
  def start(_type, _args) do
    setup_signal_handlers()
    maybe_migrate()
    validate_retention_rules!()

    children =
      [
        BtcTxFeedWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:btc_tx_feed, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BtcTxFeed.PubSub},
        MempoolSocket,
        BtcTxFeed.Repo
      ] ++
        analytics_children() ++
        [
          # Start to serve requests, typically the last entry
          BtcTxFeedWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BtcTxFeed.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BtcTxFeedWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_migrate do
    if System.get_env("RELEASE_NAME") do
      for repo <- Application.fetch_env!(:btc_tx_feed, :ecto_repos) do
        {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      end
    end
  end

  defp setup_signal_handlers do
    # Trap SIGTERM (sent by Fly.io and other process managers on graceful stop)
    # to ensure the OTP shutdown sequence runs and TxStats flushes to disk.
    # Note: SIGINT (Ctrl-C) is managed by the Erlang VM break handler and
    # cannot be intercepted here — rely on the periodic flush for dev restarts.
    System.trap_signal(:sigterm, :graceful_shutdown, fn ->
      System.stop(0)
      :ok
    end)
  end

  defp analytics_children do
    if Application.get_env(:btc_tx_feed, :start_analytics, true) do
      [BtcTxFeed.TxStats, BtcTxFeed.TxSampler]
    else
      []
    end
  end

  defp validate_retention_rules! do
    entries = Application.get_env(:btc_tx_feed, :retention_rules, [])

    if not is_list(entries) do
      raise "Invalid :retention_rules config: expected a list, got: #{inspect(entries)}"
    end

    Enum.each(entries, fn entry ->
      case BtcTxFeed.TxRetentionRules.validate_rule(entry.rule) do
        :ok ->
          :ok

        {:error, reason} ->
          raise "Invalid retention rule in config: #{reason}\n  Rule: #{inspect(entry.rule)}"
      end
    end)
  end
end
