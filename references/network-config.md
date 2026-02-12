# Integralayer Network Configuration Reference

Canonical chain parameters, endpoints, and configuration settings for the Integralayer blockchain.

## Network Overview

| Parameter | Mainnet | Testnet |
|---|---|---|
| Chain ID (Cosmos) | `integra-1` | `ormos-1` |
| Chain ID (EVM) | `26217` | `26218` |
| Binary | `intgd` | `intgd` |
| Token | IRL | IRL |
| Smallest denom | `airl` (18 decimals) | `airl` (18 decimals) |
| Cosmos RPC | https://rpc.integralayer.com | https://testnet-rpc.integralayer.com |
| EVM RPC | https://evm.integralayer.com | https://testnet-evm.integralayer.com |
| REST API | https://api.integralayer.com | https://testnet-api.integralayer.com |
| Explorer | https://explorer.integralayer.com | https://testnet.explorer.integralayer.com |

> **CRITICAL**: The token is **IRL** / **airl**. NOT ILR/ailr. This is a common source of confusion.

> **CRITICAL**: After running `intgd init`, the default EVM chain ID is **262144**, which is WRONG. You must manually set it to **26217** (mainnet) or **26218** (testnet) in `app.toml`.

## Persistent Peers

### Mainnet

```
165.227.118.77:26656
159.65.168.118:26656
104.131.34.167:26656
```

Format for `config.toml`:
```toml
persistent_peers = "<node_id>@165.227.118.77:26656,<node_id>@159.65.168.118:26656,<node_id>@104.131.34.167:26656"
```

### Testnet

```
143.198.25.105:26656
165.227.177.127:26656
167.71.173.21:26656
```

## Port Reference

| Port | Protocol | Service | Default Binding | Notes |
|---|---|---|---|---|
| 26656 | TCP | P2P (CometBFT) | `0.0.0.0:26656` | Must be open for peering |
| 26657 | TCP | RPC (CometBFT) | `tcp://127.0.0.1:26657` | Localhost by default; open cautiously |
| 26660 | TCP | Prometheus metrics | `127.0.0.1:26660` | CometBFT metrics endpoint |
| 8545 | TCP | EVM JSON-RPC (HTTP) | `0.0.0.0:8545` | Ethereum-compatible RPC |
| 8546 | TCP | EVM JSON-RPC (WS) | `0.0.0.0:8546` | Ethereum-compatible WebSocket |
| 1317 | TCP | REST API (Cosmos) | `tcp://localhost:1317` | Cosmos SDK REST/LCD |
| 9090 | TCP | gRPC | `0.0.0.0:9090` | Cosmos SDK gRPC |
| 9091 | TCP | gRPC-Web | `0.0.0.0:9091` | gRPC-Web proxy |

## Config.toml Key Settings

Located at `~/.intgd/config/config.toml`:

```toml
# P2P Configuration
[p2p]
laddr = "tcp://0.0.0.0:26656"
persistent_peers = "<node_id>@<ip>:26656,..."
addr_book_strict = true
max_num_inbound_peers = 40
max_num_outbound_peers = 10

# RPC Configuration
[rpc]
laddr = "tcp://127.0.0.1:26657"   # Keep localhost unless running a public RPC
cors_allowed_origins = []

# Consensus
[consensus]
timeout_commit = "5s"

# Prometheus Metrics
[instrumentation]
prometheus = true
prometheus_listen_addr = ":26660"
```

## App.toml Key Settings

Located at `~/.intgd/config/app.toml`:

```toml
# Minimum gas prices (REQUIRED for validators)
minimum-gas-prices = "0.0001airl"

# EVM Configuration
[evm]
# CRITICAL: Default after init is 262144 — MUST change
evm-chain-id = "26217"    # mainnet
# evm-chain-id = "26218"  # testnet

# JSON-RPC Configuration
[json-rpc]
enable = true
address = "0.0.0.0:8545"
ws-address = "0.0.0.0:8546"
api = "eth,txpool,personal,net,debug,web3"

# REST API
[api]
enable = true
swagger = false
address = "tcp://localhost:1317"

# gRPC
[grpc]
enable = true
address = "0.0.0.0:9090"

# State Sync (for faster initial sync)
[state-sync]
snapshot-interval = 1000
snapshot-keep-recent = 2
```

## Pre-deployed EVM Contracts

These contracts are available at their canonical addresses on the Integralayer EVM:

| Contract | Address | Purpose |
|---|---|---|
| Create2 Factory | `0x4e59b44847b379578588920cA78FbF26c0B4956C` | Deterministic contract deployment |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` | Batch multiple calls in one transaction |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` | Token approval management |
| Safe Singleton Factory | `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7` | Deterministic Safe deployment |

## Genesis Acquisition

```bash
# Download mainnet genesis
curl -L https://rpc.integralayer.com/genesis | jq '.result.genesis' > ~/.intgd/config/genesis.json

# Download testnet genesis
curl -L https://testnet-rpc.integralayer.com/genesis | jq '.result.genesis' > ~/.intgd/config/genesis.json

# Verify genesis hash
sha256sum ~/.intgd/config/genesis.json
```

## Peer Discovery Commands

```bash
# Get your own node ID
intgd tendermint show-node-id

# Get a peer's node ID (from their RPC)
curl -s http://<peer_ip>:26657/status | jq -r '.result.node_info.id'

# Check connected peers
curl -s http://localhost:26657/net_info | jq '.result.n_peers'

# List all connected peers with IPs
curl -s http://localhost:26657/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr | split(":") | last)"'

# Check sync status
intgd status | jq '.SyncInfo'

# Check latest block height
curl -s http://localhost:26657/status | jq '.result.sync_info.latest_block_height'
```

## Binary Source

The `intgd` binary is built from the **Integra-layer/evm** repository, NOT from chain-core. Using the wrong repository will cause AppHash mismatches.

```bash
git clone https://github.com/Integra-layer/evm.git
cd evm
make install
```
