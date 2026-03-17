# ---- Builder ----
FROM elixir:1.19-otp-28 AS builder

WORKDIR /app

# Install system build tools; exqlite NIF requires gcc + cmake
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends build-essential cmake git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Gleam v1.14.0 static Linux binary — arch is injected by BuildKit
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      GLEAM_ARCH="aarch64-unknown-linux-musl"; \
      GLEAM_SHA256="16371f8e3b45303d240758fe07f4adcb0fe444edf2f82312a24451323869730c"; \
    else \
      GLEAM_ARCH="x86_64-unknown-linux-musl"; \
      GLEAM_SHA256="5dc66abbf3eb80f209f1c261ecfc44dc1404dd8ac503e483369d37182a4fcce8"; \
    fi && \
    curl -fsSL "https://github.com/gleam-lang/gleam/releases/download/v1.14.0/gleam-v1.14.0-${GLEAM_ARCH}.tar.gz" \
      -o /tmp/gleam.tar.gz && \
    echo "${GLEAM_SHA256} */tmp/gleam.tar.gz" | sha256sum --check && \
    tar -xz -C /usr/local/bin -f /tmp/gleam.tar.gz && \
    rm /tmp/gleam.tar.gz

# Install mix_gleam archive, hex, and rebar
RUN mix archive.install hex mix_gleam "~> 0.6.2" --force && \
    mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV=prod

# Fetch dependencies (copy manifests first to maximise layer cache)
COPY mix.exs mix.lock ./

# btc_tx's Gleam test files import gleeunit. mix_gleam builds its package
# manifest from the active env's dep list, so gleeunit must be visible in prod
# for the Gleam compiler to resolve `import gleeunit` when compiling btc_tx.
# gleeunit is runtime: false so it is never included in the release.
RUN sed -i 's/only: \[:dev, :test\], runtime: false/runtime: false/' mix.exs

RUN mix deps.get

# Pre-compile Gleam packages in dependency order (same workaround as CI)
RUN mix deps.compile gleam_stdlib gleam_crypto gleeunit

# Compile remaining dependencies
RUN mix deps.compile

# Copy application source and config
COPY config/ config/
COPY priv/ priv/
COPY lib/ lib/
COPY assets/ assets/

# Compile the application first — the Phoenix LiveView compiler generates
# _build/prod/phoenix-colocated/btc_tx_feed which esbuild must resolve
RUN mix compile

# Build and digest frontend assets (tailwind + esbuild + phx.digest)
RUN mix assets.deploy

# Build the OTP release
RUN mix release

# ---- Runner ----
FROM debian:trixie-slim

WORKDIR /app

# ERTS runtime dependencies + exqlite NIF runtime
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libstdc++6 openssl ca-certificates libncurses6 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/_build/prod/rel/btc_tx_feed ./

ENV PHX_SERVER=true

CMD ["/app/bin/btc_tx_feed", "start"]
