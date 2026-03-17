defmodule BtcTxFeed.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias BtcTxFeed.MempoolSocket

  use Application

  @impl true
  def start(_type, _args) do
    maybe_migrate()

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

  defp analytics_children do
    if Application.get_env(:btc_tx_feed, :start_analytics, true) do
      [BtcTxFeed.TxStats, BtcTxFeed.TxSampler]
    else
      []
    end
  end
end
