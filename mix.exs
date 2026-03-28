defmodule BtcTxFeed.MixProject do
  use Mix.Project

  @app :btc_tx_feed

  def project do
    [
      app: @app,
      version: "0.1.0",
      elixir: "~> 1.19",
      name: "#{@app}",
      archives: [mix_gleam: "~> 0.6.2"],
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_include_path: "build/dev/erlang/#{@app}/include",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:gleam, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      prune_code_paths: false
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BtcTxFeed.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test),
    do: ["lib", "test/support", "build/dev/erlang/#{@app}/_gleam_artefacts"]

  defp elixirc_paths(_), do: ["lib", "build/dev/erlang/#{@app}/_gleam_artefacts"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:mint_web_socket, "~> 1.0"},
      {:gleam_stdlib, "~> 0.44 or ~> 1.0"},
      {:gleam_crypto, "~> 1.5"},
      {:gleeunit, "~> 1.0", runtime: false},
      {:btc_tx, git: "https://github.com/caquinn7/btc-tx.git", branch: "main"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.18"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind btc_tx_feed", "esbuild btc_tx_feed"],
      "assets.deploy": [
        "tailwind btc_tx_feed --minify",
        "esbuild btc_tx_feed --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"],
      "deps.get": ["deps.get", "gleam.deps.get", fn _ -> File.rm_rf!("deps/btc_tx/test") end],
      "deps.update": [
        "deps.update",
        "gleam.deps.get",
        fn _ -> File.rm_rf!("deps/btc_tx/test") end
      ]
    ]
  end
end
