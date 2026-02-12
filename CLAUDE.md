# Validator Skill — Claude Code Plugin

Claude Code plugin for deploying and operating Integralayer blockchain validator nodes.

## Usage

```bash
claude --plugin-dir /path/to/validator-skill
```

## Skills (4)

| Skill | Purpose |
|-------|---------|
| `deploy-validator` | Deploy validator node — Docker or bare metal |
| `validator-ops` | Day-to-day ops — status, unjail, delegate, backup, upgrade |
| `setup-caddy` | HTTPS reverse proxy with auto-TLS for RPC endpoints |
| `generate-connect-page` | Scaffold a validator monitoring landing page |

## Structure

```
validator-skill/
├── .claude-plugin/plugin.json
├── skills/                    # 4 skills (SKILL.md each)
├── references/                # Shared docs
│   ├── network-config.md      # Chain params, endpoints, peers
│   ├── security-hardening.md  # Firewall, SSH, key management
│   └── troubleshooting.md     # Common issues and fixes
└── templates/                 # Config templates
    ├── caddy/                 # Caddyfile templates
    ├── connect-page/          # HTML monitoring page
    ├── docker/                # Dockerfile, compose
    ├── network-deploy/        # Genesis, config, seeds
    └── systemd/               # Service unit files
```

## Key References

- Token: **IRL** / `airl` (NOT ILR/ailr)
- Chain ID: `integra-1` (EVM: `26217`)
- Binary: `intgd` (Cosmos SDK + EVM)
- Endpoints: `rpc.integralayer.com`, `evm.integralayer.com`, `api.integralayer.com`

## Development

This is a Claude Code plugin — edit SKILL.md files in `skills/` to modify skill behavior. Templates in `templates/` are scaffolded by skills during execution. Reference docs in `references/` are loaded as context.
