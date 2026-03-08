defmodule BtcTxFeed.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BtcTxFeedWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:btc_tx_feed, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BtcTxFeed.PubSub},
      # Start a worker by calling: BtcTxFeed.Worker.start_link(arg)
      # {BtcTxFeed.Worker, arg},
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
end
