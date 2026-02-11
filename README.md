# Integralayer Validator Node

Docker-based setup for running an [Integralayer](https://integralayer.com) validator node. Supports both **mainnet** (`integra-1`) and **testnet** (`ormos-1`).

## Prerequisites

- Docker and Docker Compose v2+
- 16 GB+ RAM
- 500 GB+ SSD (NVMe recommended)
- Ports open: 26656 (P2P), 26657 (RPC), 8545 (EVM), 1317 (REST)

## Quick Start

### Mainnet

```bash
git clone https://github.com/Integra-layer/validator-skill.git
cd validator-skill
docker compose -f docker-compose.mainnet.yml up -d
```

### Testnet

```bash
docker compose -f docker-compose.testnet.yml up -d
```

The first build compiles `intgd` from source (takes a few minutes). After that, the container automatically:
1. Initializes the node
2. Downloads genesis from the network RPC
3. Discovers and connects to peers
4. Starts syncing blocks

## Check Sync Status

```bash
# Mainnet
docker exec integra-mainnet intgd status | jq '.sync_info'

# Testnet
docker exec integra-testnet intgd status | jq '.sync_info'
```

Your node is synced when `catching_up` is `false`.

## Create Validator

Once your node is fully synced:

```bash
# 1. Create or recover a key
docker exec -it integra-mainnet intgd keys add validator --keyring-backend test

# 2. Fund the address with IRL tokens

# 3. Create the validator
docker exec -it integra-mainnet intgd tx staking create-validator \
  --amount=1000000000000000000airl \
  --pubkey=$(docker exec integra-mainnet intgd tendermint show-validator) \
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

For testnet, replace `integra-mainnet` with `integra-testnet` and `--chain-id=integra-1` with `--chain-id=ormos-1`.

## Configuration

Environment variables (set in docker-compose files):

| Variable | Default | Description |
|----------|---------|-------------|
| `CHAIN_ID` | `integra-1` | `integra-1` (mainnet) or `ormos-1` (testnet) |
| `MONIKER` | `my-integra-validator` | Your node's display name |
| `MIN_GAS_PRICES` | `0airl` | Minimum gas price for transaction acceptance |
| `PEERS_OVERRIDE` | — | Comma-separated peer list (overrides auto-discovery) |

## Monitoring

```bash
# Follow logs
docker logs -f integra-mainnet

# Current block height
docker exec integra-mainnet intgd status | jq -r '.sync_info.latest_block_height'

# Check validator signing info
docker exec integra-mainnet intgd query slashing signing-info \
  $(docker exec integra-mainnet intgd comet show-validator)
```

## Data Persistence

Chain data is stored in Docker volumes:
- `integra-mainnet-data` for mainnet
- `integra-testnet-data` for testnet

To reset a node (removes all chain data but keys are in the volume):

```bash
docker compose -f docker-compose.mainnet.yml down
docker volume rm validator-skill_integra-mainnet-data
docker compose -f docker-compose.mainnet.yml up -d
```

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| No peers connecting | Missing `--chain-id` flag | Already handled by entrypoint.sh |
| AppHash mismatch | Wrong binary version | Rebuild image: `docker compose build --no-cache` |
| Genesis hash mismatch | Modified genesis file | Reset node and let entrypoint re-download |
| Container restart loop | Check logs | `docker logs integra-mainnet --tail 50` |
| EVM RPC not accessible | Port not exposed | Verify port mapping in docker-compose |

## Network Reference

| Property | Mainnet | Testnet |
|----------|---------|---------|
| Chain ID | `integra-1` | `ormos-1` |
| EVM Chain ID | `26217` | `26218` |
| RPC | https://rpc.integralayer.com | https://testnet-rpc.integralayer.com |
| Explorer | https://explorer.integralayer.com | https://testnet.explorer.integralayer.com |
| Token | IRL (`airl`, 18 decimals) | oIRL (`airl`, 18 decimals) |

## Build from Source (without Docker)

See [SKILL.md](SKILL.md) for manual build instructions, systemd service setup, and full command reference.
