---
name: integralayer-validator
description: Set up, configure, and manage Integralayer blockchain validator nodes. Use when working with intgd binary, validator setup, staking, node configuration, or Integralayer chain operations on Ubuntu/Debian servers.
---

# Integralayer Validator Setup & Management

## Network Reference

| Property | Mainnet | Testnet |
|----------|---------|---------|
| Cosmos Chain ID | `integra-1` | `ormos-1` |
| EVM Chain ID | `26217` | `26218` |
| EVM RPC | `https://evm.integralayer.com` | `https://testnet-evm.integralayer.com` |
| Cosmos RPC | `https://rpc.integralayer.com` | `https://testnet-rpc.integralayer.com` |
| REST API | `https://api.integralayer.com` | `https://testnet-api.integralayer.com` |
| Explorer | `https://explorer.integralayer.com` | `https://testnet.explorer.integralayer.com` |
| Token | IRL (airl, 18 decimals) | oIRL (airl, 18 decimals) |
| Binary | `intgd` | `intgd` |

## Quick Start: Docker (Recommended)

```bash
git clone https://github.com/Integra-layer/validator-skill.git
cd validator-skill

# Mainnet
docker compose -f docker-compose.mainnet.yml up -d

# Testnet
docker compose -f docker-compose.testnet.yml up -d
```

The Docker setup handles binary compilation, genesis download, and peer discovery automatically.

## Quick Start: Build from Source

> **Important**: The `intgd` binary must be built from the [`Integra-layer/evm`](https://github.com/Integra-layer/evm) repository.
> Do NOT use the pre-built binary from `chain-core` releases — it is a pre-upgrade binary that does not support the `integra-1` chain.

```bash
# Prerequisites: Go 1.25+, git, build-essential
git clone https://github.com/Integra-layer/evm.git
cd evm/integra
CGO_ENABLED=1 go build -tags "netgo" \
  -ldflags "-w -s -X github.com/cosmos/cosmos-sdk/version.Name=integra \
    -X github.com/cosmos/cosmos-sdk/version.AppName=intgd" \
  -trimpath -o intgd ./cmd/intgd
sudo mv intgd /usr/local/bin/intgd

# Initialize node
intgd init <moniker> --chain-id integra-1  # mainnet
intgd init <moniker> --chain-id ormos-1    # testnet

# Download genesis (unmodified from RPC — hash must match network)
curl -s https://rpc.integralayer.com/genesis | jq '.result.genesis' > ~/.intgd/config/genesis.json
```

## System Requirements

| Spec | Minimum | Recommended |
|------|---------|-------------|
| CPU | 4 cores (2.0 GHz+) | 8+ cores |
| RAM | 16 GB | 32 GB+ |
| Disk | 500 GB SSD | 1 TB+ NVMe |
| Network | 100 Mbps | 1 Gbps |
| OS | Ubuntu 22.04+ x86_64 | Ubuntu 24.04 LTS |

### Cloud Provider Recommendations

- **DigitalOcean**: General Purpose 4vCPU / 16GB (~$96/mo)
- **AWS**: m6i.xlarge 4vCPU / 16GB (~$140/mo)
- **Hetzner**: CPX41 8vCPU / 16GB (~$28/mo)

**Required ports**: 26656 (P2P), 26657 (RPC), 8545 (EVM RPC), 1317 (REST API)

## Configuration

### Persistent Peers (Mainnet)

```bash
# Add to ~/.intgd/config/config.toml [p2p] section
persistent_peers = "<node-id>@165.227.118.77:26656,<node-id>@159.65.168.118:26656,<node-id>@104.131.34.167:26656"
```

### Persistent Peers (Testnet)

```bash
persistent_peers = "<node-id>@143.198.25.105:26656,<node-id>@165.227.177.127:26656,<node-id>@167.71.173.21:26656"
```

### Key Config Settings

```toml
# config.toml
[p2p]
laddr = "tcp://0.0.0.0:26656"
max_num_inbound_peers = 40
max_num_outbound_peers = 10

# app.toml
minimum-gas-prices = "0airl"
pruning = "default"

[json-rpc]
enable = true
address = "0.0.0.0:8545"
ws-address = "0.0.0.0:8546"
```

## Create Validator

```bash
intgd tx staking create-validator \
  --amount=1000000000000000000airl \
  --pubkey=$(intgd tendermint show-validator) \
  --moniker="<your-moniker>" \
  --chain-id=integra-1 \
  --commission-rate="0.05" \
  --commission-max-rate="0.20" \
  --commission-max-change-rate="0.01" \
  --min-self-delegation="1" \
  --gas=auto \
  --gas-adjustment=1.5 \
  --from=validator \
  --keyring-backend=test
```

## Systemd Service

```ini
# /etc/systemd/system/intgd.service
[Unit]
Description=Integralayer Node
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/intgd start --home /root/.intgd --chain-id integra-1
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable intgd
sudo systemctl start intgd
```

## Common Operations

```bash
# Check node status
intgd status | jq '.sync_info.latest_block_height'

# Check validator signing
intgd query slashing signing-info $(intgd comet show-validator)

# Unjail validator
intgd tx slashing unjail --from=validator --chain-id=integra-1 --gas=auto

# Check balances
intgd query bank balances <address>

# Delegate tokens
intgd tx staking delegate <validator-address> 1000000000000000000airl \
  --from=validator --chain-id=integra-1 --gas=auto

# Export genesis (for upgrades)
intgd export --home /root/.intgd > exported_genesis.json

# Reset chain state (dangerous - keeps keys)
intgd comet unsafe-reset-all --home /root/.intgd

# View logs
journalctl -u intgd -f --no-hostname
```

## EVM Pre-deployed Contracts

These contracts are available at standard addresses on both networks:

| Contract | Address |
|----------|---------|
| Create2 Factory | `0x4e59b44847b379578588920ca78fbf26c0b4956c` |
| Multicall3 | `0xcA11bde05977b3631167028862bE2a173976CA11` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| Safe Singleton Factory | `0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7` |

## Troubleshooting

- **CometBFT handshake failure / no peers**: Missing `--chain-id` flag on `intgd start`. This flag is **required** — without it, peer handshake silently fails.
- **AppHash mismatch**: Binary version mismatch across validators. Ensure all nodes run the same `intgd` binary (built from `Integra-layer/evm`, NOT `chain-core` releases).
- **Connection refused on 26657**: Check `laddr` in config.toml and firewall rules.
- **EVM RPC not responding**: Ensure `[json-rpc] enable = true` in app.toml and port 8545 is open.
- **Validator jailed**: Run unjail command above. Check `signing-info` for missed blocks.
- **Out of memory**: Increase RAM or enable pruning in app.toml.

## Documentation

Full docs: [docs.integralayer.com](https://docs.integralayer.com)
