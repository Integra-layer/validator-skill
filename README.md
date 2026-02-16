# Integralayer Validator Plugin

A Claude Code plugin for deploying, operating, and monitoring [Integralayer](https://integralayer.com) blockchain validator nodes.

## Install

```bash
claude --plugin-dir /path/to/validator-skill
```

## Skills

| Skill | Description |
|-------|-------------|
| **deploy-validator** | Deploy a validator node on any server — Docker or bare metal |
| **validator-ops** | Day-to-day operations — status, unjail, delegate, backup, upgrade |
| **setup-caddy** | HTTPS reverse proxy with auto-TLS |
| **generate-connect-page** | Scaffold a validator monitoring landing page |

## Quick Examples

```
# Deploy a validator (Docker or bare metal)
> Use the deploy-validator skill to set up a mainnet validator

# Check validator status
> Use validator-ops to check my validator's signing status

# Set up HTTPS for RPC endpoints
> Use setup-caddy to configure HTTPS for my validator

# Generate a connect page like integra-connect.vercel.app
> Use generate-connect-page for my validator at mynode.integralayer.com
```

## Project Structure

```
validator-skill/
├── .claude-plugin/plugin.json    # Plugin manifest
├── skills/                       # 4 skills (each with SKILL.md)
│   ├── deploy-validator/
│   ├── validator-ops/
│   ├── setup-caddy/
│   └── generate-connect-page/
├── references/                   # Shared reference docs
│   ├── network-config.md
│   ├── security-hardening.md
│   └── troubleshooting.md
├── templates/                    # Reusable config templates
│   ├── docker/
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
| Cosmos RPC | https://rpc.integralayer.com | https://testnet-rpc.integralayer.com |
| EVM RPC | https://evm.integralayer.com | https://testnet-evm.integralayer.com |
| REST API | https://api.integralayer.com | https://testnet-api.integralayer.com |
| Explorer | https://explorer.integralayer.com | https://testnet.explorer.integralayer.com |

> **Important**: The `intgd` binary must be built from [`Integra-layer/evm`](https://github.com/Integra-layer/evm). Do NOT use pre-built binaries from `chain-core` releases.

## Known Gotchas

- **EVM Chain ID**: Default after `intgd init` is `262144` (wrong). Must be set to `26217` (mainnet) or `26218` (testnet).
- **--chain-id flag**: Required on `intgd start` — peer handshake silently fails without it.
- **Token denom**: It's **IRL** / `airl`, NOT `ILR` / `ailr`.
- **Hetzner**: Do NOT use — their ToS bans cryptocurrency nodes.

## License

MIT
