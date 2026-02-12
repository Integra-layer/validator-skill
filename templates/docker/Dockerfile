# Multi-stage build for Integralayer validator node
# Builds intgd from Integra-layer/evm repo (NOT chain-core releases)

# =============================================================================
# Stage 1: Build intgd binary from source
# =============================================================================
FROM golang:1.25-bookworm AS builder

ARG TARGETARCH
ARG EVM_COMMIT=eab463c

RUN apt-get update && apt-get install -y git build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/Integra-layer/evm.git && \
    cd evm && \
    git checkout ${EVM_COMMIT}

WORKDIR /src/evm/integra
RUN CGO_ENABLED=1 go build \
    -tags "netgo" \
    -ldflags "-w -s \
      -X github.com/cosmos/cosmos-sdk/version.Name=integra \
      -X github.com/cosmos/cosmos-sdk/version.AppName=intgd \
      -X github.com/cosmos/cosmos-sdk/version.Version=1.0.0 \
      -X github.com/cosmos/cosmos-sdk/version.Commit=${EVM_COMMIT}" \
    -trimpath \
    -o /build/intgd ./cmd/intgd

# =============================================================================
# Stage 2: Runtime
# =============================================================================
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl jq bash ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/intgd /usr/local/bin/intgd
RUN chmod +x /usr/local/bin/intgd

# Persistent data directory
VOLUME ["/root/.intgd"]

# P2P | RPC | EVM RPC | EVM WS | REST API
EXPOSE 26656 26657 8545 8546 1317

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
