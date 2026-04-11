import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/btc_tx_feed start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :btc_tx_feed, BtcTxFeedWeb.Endpoint, server: true
end

config :btc_tx_feed, BtcTxFeedWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Decode policy resource limits for btc_tx parsing.
# Default values here must match the defaults in BtcTxFeed.DecodePolicy.
witness_items_limit =
  case System.get_env("DECODE_POLICY_WITNESS_ITEMS_PER_INPUT") do
    nil -> :none
    val -> {:some, String.to_integer(val)}
  end

witness_size_limit =
  case System.get_env("DECODE_POLICY_WITNESS_SIZE_PER_INPUT") do
    nil -> :none
    val -> {:some, String.to_integer(val)}
  end

config :btc_tx_feed, :decode_policy,
  max_tx_size: String.to_integer(System.get_env("DECODE_POLICY_MAX_TX_SIZE", "400000")),
  max_vin_count: String.to_integer(System.get_env("DECODE_POLICY_MAX_VIN_COUNT", "100000")),
  max_vout_count: String.to_integer(System.get_env("DECODE_POLICY_MAX_VOUT_COUNT", "100000")),
  max_script_size: String.to_integer(System.get_env("DECODE_POLICY_MAX_SCRIPT_SIZE", "10000")),
  max_witness_items_per_input: witness_items_limit,
  max_witness_size_per_input: witness_size_limit

# Retention rules — loaded from a file on the persistent volume.
# The file must evaluate to a list of entry maps understood by
# BtcTxFeed.TxRetentionRules, where each entry includes :code, :label,
# :limit, and :rule. If the file does not exist, the empty default from
# config.exs applies and no transactions are retained.
default_rules_path =
  if config_env() == :prod do
    "/data/retention_rules.exs"
  else
    Path.expand("../data/retention_rules.exs", __DIR__)
  end

rules_path = System.get_env("RETENTION_RULES_PATH") || default_rules_path

if File.exists?(rules_path) do
  {entries, _bindings} = Code.eval_file(rules_path)

  if not is_list(entries) do
    raise "#{rules_path} must evaluate to a list, got: #{inspect(entries)}"
  end

  Enum.each(entries, fn entry ->
    required = [:code, :label, :limit, :rule]
    missing = Enum.reject(required, &Map.has_key?(entry, &1))

    if missing != [] do
      raise "retention_rules entry is missing keys #{inspect(missing)}: #{inspect(entry)}"
    end
  end)

  config :btc_tx_feed, :retention_rules, entries
end

if config_env() != :test do
  default_database_path =
    if config_env() == :prod do
      "/data/btc_tx_feed.db"
    else
      Path.expand("../data/btc_tx_feed.db", __DIR__)
    end

  database_path = System.get_env("DATABASE_PATH") || default_database_path
  config :btc_tx_feed, BtcTxFeed.Repo, database: database_path
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :btc_tx_feed, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :btc_tx_feed, BtcTxFeedWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :btc_tx_feed, BtcTxFeedWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :btc_tx_feed, BtcTxFeedWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :btc_tx_feed, BtcTxFeed.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
