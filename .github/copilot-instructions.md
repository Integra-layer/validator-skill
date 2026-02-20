# Validator Skill

Operations runbook and skill definition for managing Integra Layer validator nodes. Contains documentation, scripts, and configuration templates for validator setup and maintenance.

## Purpose

This repo serves as a Claude Code skill (SKILL.md) and operational reference for:
- Validator node setup and configuration
- Staking operations (delegate, redelegate, undelegate)
- Monitoring and alerting
- Key management and backup procedures
- Upgrade procedures

## Chain Context

- **Token:** IRL (smallest unit: `airl`, 1 IRL = 10^18 airl)
- **CRITICAL:** Token is IRL/airl, NOT ILR/ailr
- **Mainnet:** `integra-1` (EVM Chain ID: `26217`)
- **Testnet:** `integra-testnet-1` (EVM Chain ID: `26218`)
- **Binary:** `intgd` (Integra daemon)
- **Min gas price:** `1000000000airl` (~1 gwei) on testnet

## Key Files

- `SKILL.md` — Full validator operations runbook
- Scripts for common validator operations

## Documentation Standards

- All commands must include the correct `--chain-id` flag
- Gas prices must use `airl` denomination (not `IRL`)
- Include both mainnet and testnet variants where applicable
- Security-sensitive operations (key export, validator creation) must include safety warnings
