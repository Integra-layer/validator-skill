# Integralayer Validator Plugin

A Claude Code plugin for deploying, operating, and monitoring [Integralayer](https://integralayer.com) blockchain validator nodes.

## Skills

| Skill | Description |
|-------|-------------|
| **deploy-validator** | Deploy a validator node on any server — Docker or bare metal |
| **validator-ops** | Day-to-day operations — status, unjail, delegate, backup, upgrade |
| **setup-caddy** | HTTPS reverse proxy with auto-TLS |
| **generate-connect-page** | Scaffold a validator monitoring landing page |

## Quick Start (Docker)

No Claude Code required — run a validator node with Docker in minutes:

```bash
# Clone the repo
git clone https://github.com/Integra-layer/validator-skill.git
cd validator-skill

# Testnet
docker compose -f docker-compose.testnet.yml up -d

# Mainnet
docker compose -f docker-compose.mainnet.yml up -d

# Check sync progress (wait for catching_up: false)
docker exec integra-testnet intgd status | jq '.sync_info.catching_up'

# Follow logs
docker logs -f integra-testnet
```

> **Custom moniker**: `MONIKER=mynode docker compose -f docker-compose.testnet.yml up -d`

> **After updating**: `git pull && docker compose -f docker-compose.testnet.yml build --no-cache && docker compose -f docker-compose.testnet.yml up -d`

> **Requires**: Docker 20.10+ with Compose V2 (`docker compose`, NOT `docker-compose` with hyphen)

For detailed setup including bare-metal and validator creation, see [`skills/deploy-validator/SKILL.md`](skills/deploy-validator/SKILL.md).

## Claude Code Plugin Usage

If using Claude Code, install the plugin for guided deployment and operations:

```bash
claude --plugin-dir /path/to/validator-skill
```

| Skill | Description |
|-------|-------------|
| **deploy-validator** | Deploy a validator node on any server — Docker or bare metal |
| **validator-ops** | Day-to-day operations — status, unjail, delegate, backup, upgrade |
| **setup-caddy** | HTTPS reverse proxy with auto-TLS |
| **generate-connect-page** | Scaffold a validator monitoring landing page |

## Project Structure

```
validator-skill/
├── docker-compose.testnet.yml   # Run from repo root (wraps templates/docker/)
├── docker-compose.mainnet.yml   # Run from repo root (wraps templates/docker/)
├── .claude-plugin/plugin.json   # Plugin manifest
├── skills/                      # 4 skills (each with SKILL.md)
│   ├── deploy-validator/
│   ├── validator-ops/
│   ├── setup-caddy/
│   └── generate-connect-page/
├── references/                  # Shared reference docs
│   ├── network-config.md
│   ├── security-hardening.md
│   └── troubleshooting.md
├── templates/                   # Reusable config templates
│   ├── docker/                  # Dockerfile, entrypoint, compose files
│   ├── systemd/
│   ├── caddy/
│   ├── connect-page/
│   └── network-deploy/
├── README.md
├── CHANGELOG.md
└── LICENSE
```

## Network Reference

| Property | Mainnet | Testnet |
|----------|---------|---------|
| Chain ID | `integra-1` | `integra-testnet-1` |
| EVM Chain ID | `26217` | `26218` |
| Token | IRL (`airl`, 18 decimals) | oIRL (`airl`, 18 decimals) |
| Cosmos RPC | https://rpc.integralayer.com | https://ormos.integralayer.com/cometbft |
| EVM RPC | https://evm.integralayer.com | https://ormos.integralayer.com/rpc |
| REST API | https://api.integralayer.com | https://ormos.integralayer.com/rest |
| EVM WebSocket | wss://ws.integralayer.com | wss://ormos.integralayer.com/ws |
| Explorer | https://explorer.integralayer.com | https://testnet.explorer.integralayer.com |
| Blockscout (EVM) | https://blockscout.integralayer.com | https://testnet.blockscout.integralayer.com |

> **Important**: The `intgd` binary must be built from [`Integra-layer/evm`](https://github.com/Integra-layer/evm). Do NOT use pre-built binaries from `chain-core` releases.

## Known Gotchas

- **EVM Chain ID**: Default after `intgd init` is `262144` (wrong). Must be set to `26217` (mainnet) or `26218` (testnet).
- **--chain-id flag**: Required on `intgd start` — peer handshake silently fails without it.
- **Token denom**: It's **IRL** / `airl`, NOT `ILR` / `ailr`.
- **Hetzner**: Do NOT use — their ToS bans cryptocurrency nodes.

## License

MIT
