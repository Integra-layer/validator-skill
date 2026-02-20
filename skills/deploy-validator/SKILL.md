---
name: deploy-validator
description: Deploy an Integralayer validator node on any server — bare metal, VPS, or cloud (Docker or systemd)
---

# Deploy Validator

Set up an Integralayer validator node from scratch on any Linux server. Supports two modes:
- **Docker** (fastest) — single command, auto-builds binary
- **Bare metal** (full control) — build from source, systemd service

Works on any provider: AWS, DigitalOcean, Hetzner alternatives, bare metal, etc.

## Prerequisites

| Spec | Minimum | Recommended |
|------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 16 GB | 32 GB+ |
| Disk | 500 GB SSD | 1 TB+ NVMe |
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |

## Choose Your Network

| Property | Mainnet | Testnet |
|----------|---------|---------|
| Chain ID | `integra-1` | `integra-testnet-1` |
| EVM Chain ID | `26217` | `26218` |
| RPC | `https://rpc.integralayer.com` | `https://testnet-rpc.integralayer.com` |
| Token | IRL (`airl`) | oIRL (`airl`) |

## Option A: Docker (Recommended)

### Step 1: Clone and Start

```bash
git clone https://github.com/Integra-layer/validator-skill.git
cd validator-skill

# Mainnet
docker compose -f templates/docker/docker-compose.mainnet.yml up -d

# Testnet
docker compose -f templates/docker/docker-compose.testnet.yml up -d
```

First build compiles `intgd` from source (~5 min). The container automatically:
1. Initializes the node
2. Downloads genesis from network RPC
3. Discovers and connects to peers
4. Fixes the EVM chain ID (262144 → 26217 mainnet / 26218 testnet)
5. Configures state sync (downloads recent snapshot instead of replaying from genesis)
6. Starts syncing blocks

### Step 2: Customize (Optional)

Override environment variables:

```bash
MONIKER=my-validator CHAIN_ID=integra-1 docker compose -f templates/docker/docker-compose.mainnet.yml up -d
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CHAIN_ID` | `integra-1` | Chain ID |
| `MONIKER` | `my-integra-validator` | Node display name |
| `MIN_GAS_PRICES` | `0airl` | Minimum gas price |
| `STATE_SYNC` | `true` | Use state sync instead of block replay |
| `PEERS_OVERRIDE` | — | Manual peer list |

### Step 3: Wait for Sync

```bash
# Check sync status
docker exec integra-mainnet intgd status | jq '.sync_info'

# Follow logs
docker logs -f integra-mainnet

# Wait until catching_up: false
watch -n 5 'docker exec integra-mainnet intgd status 2>/dev/null | jq -r ".sync_info | \"height: \\(.latest_block_height) catching_up: \\(.catching_up)\""'
```

### Step 4: Create Validator

Once `catching_up: false`:

```bash
# Create key inside container
docker exec -it integra-mainnet intgd keys add validator --keyring-backend test

# Fund the address with IRL tokens, then:

# Get validator pubkey
docker exec integra-mainnet intgd comet show-validator --home /root/.intgd

# Create validator.json (replace <PUBKEY>)
docker exec -it integra-mainnet bash -c 'cat > /root/validator.json << EOF
{
  "pubkey": <PUBKEY_JSON>,
  "amount": "100000000000000000000airl",
  "moniker": "your-moniker",
  "identity": "",
  "website": "",
  "security": "",
  "details": "",
  "commission-rate": "0.05",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF'

# Submit
docker exec integra-mainnet intgd tx staking create-validator /root/validator.json \
  --from=validator --chain-id=integra-1 --gas=auto --gas-adjustment=1.5 \
  --gas-prices=1000000000airl --keyring-backend=test --home=/root/.intgd -y
```

---

## Option B: Bare Metal / VPS

### Step 1: Install Go and Build Tools

```bash
sudo apt update && sudo apt install -y build-essential git curl jq

# Install Go 1.25+
wget https://go.dev/dl/go1.25.5.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.25.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
source ~/.bashrc
go version
```

### Step 2: Build intgd

> **Critical**: Must build from `Integra-layer/evm`, NOT `chain-core` releases.

```bash
git clone https://github.com/Integra-layer/evm.git
cd evm/integra
CGO_ENABLED=1 go build -tags "netgo" \
  -ldflags "-w -s -X github.com/cosmos/cosmos-sdk/version.Name=integra \
    -X github.com/cosmos/cosmos-sdk/version.AppName=intgd" \
  -trimpath -o intgd ./cmd/intgd
sudo mv intgd /usr/local/bin/intgd
intgd version
```

### Step 3: Initialize Node

```bash
CHAIN_ID="integra-1"  # or "integra-testnet-1" for testnet
RPC="https://rpc.integralayer.com"  # or testnet-rpc for testnet

intgd init "my-validator" --chain-id "$CHAIN_ID"
```

### Step 4: Download Genesis

```bash
curl -s "$RPC/genesis" | jq '.result.genesis' > ~/.intgd/config/genesis.json
```

### Step 5: Configure Node

```bash
# Auto-discover peers
PEERS=$(curl -s "$RPC/net_info" | jq -r '.result.peers[] | .node_info.id + "@" + .remote_ip + ":26656"' | head -5 | paste -sd,)
sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" ~/.intgd/config/config.toml

# Bind RPC to all interfaces
sed -i 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|' ~/.intgd/config/config.toml

# Enable EVM JSON-RPC
sed -i 's/address = "127.0.0.1:8545"/address = "0.0.0.0:8545"/' ~/.intgd/config/app.toml
sed -i 's/ws-address = "127.0.0.1:8546"/ws-address = "0.0.0.0:8546"/' ~/.intgd/config/app.toml

# Set minimum gas prices
sed -i 's/minimum-gas-prices = ""/minimum-gas-prices = "0airl"/' ~/.intgd/config/app.toml

# FIX EVM chain ID (default is WRONG)
# Use 26217 for mainnet, 26218 for testnet
sed -i 's/evm-chain-id = 262144/evm-chain-id = 26217/' ~/.intgd/config/app.toml
```

### Step 6: Firewall

```bash
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 26656/tcp comment 'P2P'
sudo ufw allow 26657/tcp comment 'RPC'
sudo ufw allow 8545/tcp comment 'EVM RPC'
sudo ufw allow 1317/tcp comment 'REST API'
sudo ufw --force enable
```

> **Validators**: For maximum security, only open 26656 (P2P) publicly. Access other ports via SSH tunnel or reverse proxy.

### Step 7: Create Systemd Service

```bash
# Create a dedicated user (recommended)
sudo useradd -m -s /bin/bash integra
sudo cp /usr/local/bin/intgd /usr/local/bin/
sudo cp -r ~/.intgd /home/integra/.intgd
sudo chown -R integra:integra /home/integra/.intgd

# Install service (uses templates/systemd/intgd.service as reference)
sudo tee /etc/systemd/system/intgd.service > /dev/null <<'EOF'
[Unit]
Description=Integralayer Node
After=network-online.target
Wants=network-online.target

[Service]
User=integra
Group=integra
Type=simple
ExecStart=/usr/local/bin/intgd start --home /home/integra/.intgd --chain-id integra-1
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable intgd
sudo systemctl start intgd
```

### Step 8: Wait for Sync

```bash
# Check sync status
intgd status | jq '.sync_info'

# Follow logs
journalctl -u intgd -f --no-hostname

# Wait until catching_up: false
watch -n 5 'intgd status 2>/dev/null | jq -r ".sync_info | \"height: \(.latest_block_height) catching_up: \(.catching_up)\""'
```

### Step 9: Create Validator

Once fully synced:

```bash
# Create key
intgd keys add validator --keyring-backend test

# Fund the address with IRL tokens

# Get pubkey
intgd comet show-validator --home /home/integra/.intgd

# Create validator.json
cat > /tmp/validator.json << 'EOF'
{
  "pubkey": <PUBKEY_JSON_FROM_ABOVE>,
  "amount": "100000000000000000000airl",
  "moniker": "your-moniker",
  "identity": "",
  "website": "",
  "security": "",
  "details": "",
  "commission-rate": "0.05",
  "commission-max-rate": "0.20",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF

# Submit (--gas-prices is required)
intgd tx staking create-validator /tmp/validator.json \
  --from=validator --chain-id=integra-1 --gas=auto --gas-adjustment=1.5 \
  --gas-prices=1000000000airl --keyring-backend=test \
  --home=/home/integra/.intgd -y

# Verify
curl -s 'http://localhost:1317/cosmos/staking/v1beta1/validators?status=BOND_STATUS_BONDED' \
  | jq '.validators[] | {moniker: .description.moniker, tokens: .tokens}'
```

---

## Post-Setup Checklist

- [ ] Node synced (`catching_up: false`)
- [ ] Validator active and signing blocks
- [ ] Keys backed up (see `validator-ops` skill)
- [ ] Firewall configured
- [ ] HTTPS reverse proxy set up (see `setup-caddy` skill)
- [ ] Monitoring page deployed (see `generate-connect-page` skill)

## Common Gotchas

| Issue | Fix |
|-------|-----|
| EVM chain ID 262144 | Must be 26217 (mainnet) or 26218 (testnet) in app.toml |
| No peers / handshake failure | Add `--chain-id` to `intgd start` |
| Wrong binary | Build from `Integra-layer/evm`, NOT `chain-core` |
| Token denom confusion | It's **IRL** / `airl`, NOT ILR/ailr |

## Cross-References

- `validator-ops` — Day-to-day operations, backup, unjail
- `setup-caddy` — HTTPS reverse proxy for RPC endpoints
- `generate-connect-page` — Monitoring landing page
- `references/network-config.md` — All chain parameters
- `references/troubleshooting.md` — Detailed problem solving
