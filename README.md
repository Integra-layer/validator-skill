# Integralayer Validator Node

Run an [Integralayer](https://integralayer.com) validator node on **mainnet** (`integra-1`) or **testnet** (`ormos-1`). Choose the deployment method that fits your setup.

> **Important**: The `intgd` binary must be built from [`Integra-layer/evm`](https://github.com/Integra-layer/evm).
> Do NOT use the pre-built binary from `chain-core` releases — it is a pre-upgrade binary that does not support `integra-1`.

## Network Reference

| Property | Mainnet | Testnet |
|----------|---------|---------|
| Chain ID | `integra-1` | `ormos-1` |
| EVM Chain ID | `26217` | `26218` |
| Cosmos RPC | https://rpc.integralayer.com | https://testnet-rpc.integralayer.com |
| EVM RPC | https://evm.integralayer.com | https://testnet-evm.integralayer.com |
| REST API | https://api.integralayer.com | https://testnet-api.integralayer.com |
| Explorer | https://explorer.integralayer.com | https://testnet.explorer.integralayer.com |
| Token | IRL (`airl`, 18 decimals) | oIRL (`airl`, 18 decimals) |

## System Requirements

| Spec | Minimum | Recommended |
|------|---------|-------------|
| CPU | 4 cores (2.0 GHz+) | 8+ cores |
| RAM | 16 GB | 32 GB+ |
| Disk | 500 GB SSD | 1 TB+ NVMe |
| Network | 100 Mbps | 1 Gbps |
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |

**Required ports**: 26656 (P2P), 26657 (RPC), 8545 (EVM RPC), 1317 (REST API)

### Cloud Provider Recommendations

- **AWS**: m6i.xlarge 4vCPU / 16GB (~$140/mo) — battle-tested for validators
- **DigitalOcean**: General Purpose 4vCPU / 16GB (~$96/mo)

> **Warning**: Do NOT use Hetzner. Their ToS explicitly bans cryptocurrency nodes, and they have shut down 1000+ validators without warning.

---

## Option A: Docker (Recommended)

The fastest way to get running. Handles binary compilation, genesis download, and peer discovery automatically.

### Quick Start

```bash
git clone https://github.com/Integra-layer/validator-skill.git
cd validator-skill

# Mainnet
docker compose -f docker-compose.mainnet.yml up -d

# Testnet
docker compose -f docker-compose.testnet.yml up -d
```

The first build compiles `intgd` from source (~5 min). After that, the container:
1. Initializes the node with your moniker
2. Downloads genesis from the network RPC
3. Auto-discovers and connects to peers
4. Starts syncing blocks

### Docker Configuration

Edit environment variables in the compose file or override them:

```bash
MONIKER=my-node CHAIN_ID=integra-1 docker compose -f docker-compose.mainnet.yml up -d
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CHAIN_ID` | `integra-1` | `integra-1` (mainnet) or `ormos-1` (testnet) |
| `MONIKER` | `my-integra-validator` | Your node's display name |
| `MIN_GAS_PRICES` | `0airl` | Minimum gas price for tx acceptance |
| `PEERS_OVERRIDE` | — | Comma-separated peer list (overrides auto-discovery) |

### Docker Operations

```bash
# Check sync status
docker exec integra-mainnet intgd status | jq '.sync_info'

# Follow logs
docker logs -f integra-mainnet

# Current block height
docker exec integra-mainnet intgd status | jq -r '.sync_info.latest_block_height'

# Reset node (removes chain data, re-syncs from scratch)
docker compose -f docker-compose.mainnet.yml down
docker volume rm validator-skill_integra-mainnet-data
docker compose -f docker-compose.mainnet.yml up -d
```

---

## Option B: Build from Source (VPS / EC2 / Bare Metal)

For operators who want full control over the node process and system configuration.

### 1. Install Prerequisites

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y build-essential git curl jq

# Install Go 1.25+
wget https://go.dev/dl/go1.25.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.25.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
```

### 2. Build intgd

```bash
git clone https://github.com/Integra-layer/evm.git
cd evm/integra
CGO_ENABLED=1 go build -tags "netgo" \
  -ldflags "-w -s -X github.com/cosmos/cosmos-sdk/version.Name=integra \
    -X github.com/cosmos/cosmos-sdk/version.AppName=intgd" \
  -trimpath -o intgd ./cmd/intgd
sudo mv intgd /usr/local/bin/intgd
intgd version  # verify
```

### 3. Initialize Node

```bash
# Mainnet
CHAIN_ID="integra-1"
RPC="https://rpc.integralayer.com"

# Or testnet:
# CHAIN_ID="ormos-1"
# RPC="https://testnet-rpc.integralayer.com"

intgd init "my-validator" --chain-id "$CHAIN_ID"
```

### 4. Download Genesis

```bash
# Download unmodified genesis from RPC (hash must match network exactly)
curl -s "$RPC/genesis" | jq '.result.genesis' > ~/.intgd/config/genesis.json
```

### 5. Configure Peers

```bash
# Auto-discover peers from the network
PEERS=$(curl -s "$RPC/net_info" | jq -r '.result.peers[] | .node_info.id + "@" + .remote_ip + ":26656"' | head -5 | paste -sd,)
sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" ~/.intgd/config/config.toml
echo "Peers: $PEERS"
```

### 6. Configure Ports and Gas

```bash
# Bind RPC to all interfaces (for remote access)
sed -i 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|' ~/.intgd/config/config.toml

# Enable EVM JSON-RPC
sed -i 's/address = "127.0.0.1:8545"/address = "0.0.0.0:8545"/' ~/.intgd/config/app.toml
sed -i 's/ws-address = "127.0.0.1:8546"/ws-address = "0.0.0.0:8546"/' ~/.intgd/config/app.toml

# Set minimum gas prices
sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0airl"/' ~/.intgd/config/app.toml
```

### 7. Set Up Systemd Service

```bash
sudo tee /etc/systemd/system/intgd.service > /dev/null <<'EOF'
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
EOF

sudo systemctl daemon-reload
sudo systemctl enable intgd
sudo systemctl start intgd
```

> For testnet, change `--chain-id integra-1` to `--chain-id ormos-1` in ExecStart.

### Bare Metal Operations

```bash
# Check sync status
intgd status | jq '.sync_info'

# Follow logs
journalctl -u intgd -f --no-hostname

# Restart node
sudo systemctl restart intgd

# Reset chain state (dangerous - keeps keys)
sudo systemctl stop intgd
intgd comet unsafe-reset-all --home /root/.intgd
sudo systemctl start intgd
```

---

## Create Validator

Once your node is fully synced (`catching_up: false`), create a validator on either deployment:

```bash
# If using Docker, prefix commands with: docker exec -it integra-mainnet

# 1. Create a key
intgd keys add validator --keyring-backend test

# 2. Fund the address with IRL tokens (mainnet) or oIRL (testnet)

# 3. Create the validator
intgd tx staking create-validator \
  --amount=1000000000000000000airl \
  --pubkey=$(intgd tendermint show-validator) \
  --moniker="your-moniker" \
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

For testnet, use `--chain-id=ormos-1`.

## Common Operations

```bash
# Check validator signing info
intgd query slashing signing-info $(intgd comet show-validator)

# Unjail validator
intgd tx slashing unjail --from=validator --chain-id=integra-1 --gas=auto

# Check balances
intgd query bank balances <address>

# Delegate tokens
intgd tx staking delegate <validator-address> 1000000000000000000airl \
  --from=validator --chain-id=integra-1 --gas=auto
```

## AWS Deployment Notes

If deploying on AWS EC2, keep these gotchas in mind:

- **NVMe device naming**: Nitro-based instances (m6i, c6i, etc.) expose EBS volumes as `/dev/nvme*`, NOT `/dev/xvdf`. Use `lsblk` to find the correct device name before formatting.
- **User**: EC2 Ubuntu instances use `ubuntu` user, not `root`. Use `sudo` for all `intgd` operations.
- **Security groups**: Open ports 26656 (P2P), 26657 (RPC), 8545 (EVM RPC), 1317 (REST API) in your security group.
- **Token denom**: The token is **IRL** (base: `airl`), NOT `ILR`/`ailr`. Many early deployment scripts had this transposed.

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| No peers / handshake failure | Missing `--chain-id` flag on `intgd start` | Add `--chain-id integra-1` (or `ormos-1`) — **required** |
| AppHash mismatch | Wrong binary | Must build from `Integra-layer/evm`, NOT `chain-core` releases |
| Genesis hash mismatch | Modified genesis | Re-download from RPC: `curl -s $RPC/genesis \| jq '.result.genesis'` |
| Connection refused 26657 | RPC bound to localhost | Set `laddr = "tcp://0.0.0.0:26657"` in config.toml |
| EVM RPC not responding | JSON-RPC disabled | Set `enable = true` and `address = "0.0.0.0:8545"` in app.toml |
| Validator jailed | Missed blocks | `intgd tx slashing unjail ...` — check `signing-info` |
| Out of memory | RAM too low | Increase RAM or enable pruning in app.toml |

## Reference

- Full command reference for AI agents: [SKILL.md](SKILL.md)
- Documentation: [docs.integralayer.com](https://docs.integralayer.com)
