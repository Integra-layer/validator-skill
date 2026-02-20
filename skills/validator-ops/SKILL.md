---
name: validator-ops
description: Day-to-day Integralayer validator operations — status, unjail, delegate, backup, upgrade
---

# Integralayer Validator Operations

Day-to-day operational commands for managing an Integralayer validator node. This skill is organized by operation type. All commands show both mainnet and testnet variants where applicable.

## Conventions

Throughout this skill:
- `HOME` refers to the intgd home directory (e.g., `/root/.intgd` or `/home/integra/.intgd`)
- `KEY_NAME` is the key alias (typically `validator`)
- Mainnet chain ID: `integra-1` (EVM chain ID: `26217`)
- Testnet chain ID: `integra-testnet-1` (EVM chain ID: `26218`)
- Token denom: `airl` (18 decimals; 1 IRL = `1000000000000000000airl`)
- `--keyring-backend=test` is used for all signing operations
- `--gas-prices=1000000000airl` is required for transaction submission

Adjust `--home`, `--chain-id`, and key names to match your setup.

---

## Status & Monitoring

### Check Node Sync Status

```bash
# Full sync info
intgd status --home $HOME | jq '.sync_info'

# Just the latest block height
intgd status --home $HOME | jq '.sync_info.latest_block_height'

# Is the node still catching up?
intgd status --home $HOME | jq '.sync_info.catching_up'
# false = fully synced, true = still syncing

# Via RPC (alternative)
curl -s http://localhost:26657/status | jq '.result.sync_info'
```

### Check Validator Signing Info

```bash
# Get signing info (missed blocks, jailed status)
intgd query slashing signing-info \
  $(intgd comet show-validator --home $HOME) \
  --home $HOME

# Key fields:
# - missed_blocks_counter: number of missed blocks in the current window
# - jailed_until: if jailed, when the jail period ends
# - tombstoned: if true, validator is permanently removed (double-sign)
```

### View Peers

```bash
# Number of connected peers
curl -s http://localhost:26657/net_info | jq '.result.n_peers'

# List all connected peers with IPs
curl -s http://localhost:26657/net_info | jq -r '.result.peers[] | "\(.node_info.id)@\(.remote_ip):\(.node_info.listen_addr | split(":") | last)"'

# Get your own node ID
intgd tendermint show-node-id --home $HOME

# Check a specific peer's status
curl -s http://<peer_ip>:26657/status | jq '.result.node_info'
```

### Check Balances

```bash
# Check validator account balance
intgd query bank balances $(intgd keys show $KEY_NAME -a --keyring-backend=test --home $HOME)

# Check a specific address
intgd query bank balances <integra1_address>

# Check balances in human-readable format (divide by 1e18 for IRL)
intgd query bank balances $(intgd keys show $KEY_NAME -a --keyring-backend=test --home $HOME) -o json | \
  jq '.balances[] | select(.denom=="airl") | .amount | tonumber / 1e18'
```

### View Validator Info

```bash
# Get your validator operator address
intgd keys show $KEY_NAME --bech val --keyring-backend=test --home $HOME -a

# Query your validator details
intgd query staking validator <integravaloper_address> --home $HOME

# List all active validators
intgd query staking validators --status=BOND_STATUS_BONDED --limit=100 --home $HOME

# Check your validator's rank/power
intgd query staking validators --status=BOND_STATUS_BONDED --limit=100 --home $HOME -o json | \
  jq '[.validators[] | {moniker: .description.moniker, tokens: .tokens}] | sort_by(.tokens | tonumber) | reverse | to_entries[] | "\(.key+1). \(.value.moniker) - \(.value.tokens)"'
```

---

## Staking Operations

### Delegate Tokens

```bash
# Self-delegate additional tokens to your validator
# Example: delegate 10 IRL (10 * 1e18 airl)
intgd tx staking delegate <integravaloper_address> 10000000000000000000airl \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y

# Testnet variant: --chain-id=integra-testnet-1
```

### Redelegate

Move stake from one validator to another without unbonding delay.

```bash
intgd tx staking redelegate <src_valoper> <dst_valoper> 10000000000000000000airl \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y
```

> **Note**: Redelegated tokens cannot be redelegated again until the original unbonding period completes.

### Unbond (Undelegate)

```bash
intgd tx staking unbond <integravaloper_address> 10000000000000000000airl \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y
```

> **WARNING**: Unbonding takes 21 days. During this period, tokens are locked and earn no rewards. Reducing self-delegation below `min-self-delegation` will jail the validator.

### Withdraw Rewards

```bash
# Withdraw staking rewards
intgd tx distribution withdraw-rewards <integravaloper_address> \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y

# Withdraw rewards AND commission (for validator operators)
intgd tx distribution withdraw-rewards <integravaloper_address> \
  --commission \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y

# Check outstanding rewards
intgd query distribution rewards $(intgd keys show $KEY_NAME -a --keyring-backend=test --home $HOME) --home $HOME

# Check outstanding commission
intgd query distribution commission <integravaloper_address> --home $HOME
```

---

## Validator Management

### Unjail Validator

A validator is jailed when it misses too many blocks (downtime) or double-signs.

```bash
# Check if jailed
intgd query slashing signing-info \
  $(intgd comet show-validator --home $HOME) \
  --home $HOME
# Look for: jailed_until field (if in the future, still jailed)

# Unjail (only works after the jail period has passed)
intgd tx slashing unjail \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y

# Testnet variant: --chain-id=integra-testnet-1
```

Common jail reasons:
- **Downtime**: Node was offline and missed too many blocks in the signing window. Fix the node, wait for jail period to expire, then unjail.
- **Double-signing**: Node signed two different blocks at the same height. This results in **tombstoning** -- the validator is permanently removed and cannot be unjailed. This usually happens when `priv_validator_key.json` is running on two machines simultaneously.

### Edit Validator

```bash
# Update moniker
intgd tx staking edit-validator \
  --moniker="new-moniker-name" \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y

# Update commission rate (must respect max-change-rate per day)
intgd tx staking edit-validator \
  --commission-rate="0.08" \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y

# Update details, website, identity (Keybase ID for avatar)
intgd tx staking edit-validator \
  --details="Reliable validator since genesis" \
  --website="https://example.com" \
  --identity="<keybase_16_char_id>" \
  --from=$KEY_NAME \
  --chain-id=integra-1 \
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \
  --keyring-backend=test \
  --home=$HOME \
  -y
```

> **Note**: Commission rate changes are limited by `commission-max-change-rate` (set at validator creation, cannot be changed). You can only change commission once every 24 hours.

### Check Validator Status Summary

```bash
# One-liner status check
echo "=== Node ===" && \
intgd status --home $HOME 2>/dev/null | jq '{latest_block: .sync_info.latest_block_height, catching_up: .sync_info.catching_up, voting_power: .validator_info.voting_power}' && \
echo "=== Signing ===" && \
intgd query slashing signing-info $(intgd comet show-validator --home $HOME) --home $HOME 2>/dev/null | grep -E "missed_blocks|jailed|tombstoned" && \
echo "=== Peers ===" && \
curl -s http://localhost:26657/net_info | jq '.result.n_peers'
```

---

## Backup & Restore

### Backup Critical Files

These three items are essential and must be backed up securely:

```bash
BACKUP_DIR="$HOME/integra-backup-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# 1. Validator private key (MOST CRITICAL -- signs blocks)
cp /home/integra/.intgd/config/priv_validator_key.json "$BACKUP_DIR/"

# 2. Node key (node identity)
cp /home/integra/.intgd/config/node_key.json "$BACKUP_DIR/"

# 3. Keyring (transaction signing keys)
cp -r /home/integra/.intgd/keyring-test/ "$BACKUP_DIR/"

# Verify
ls -la "$BACKUP_DIR/"
sha256sum "$BACKUP_DIR/priv_validator_key.json"
```

> **WARNING**: `priv_validator_key.json` MUST NEVER exist on two running nodes simultaneously. This causes double-signing, which results in permanent slashing (tombstoning).

> **Recommendation**: Store backups encrypted on a separate machine or offline medium. Never commit keys to git.

### Restore from Backup

```bash
# Stop the node first
sudo systemctl stop intgd

# Restore files
cp "$BACKUP_DIR/priv_validator_key.json" /home/integra/.intgd/config/
cp "$BACKUP_DIR/node_key.json" /home/integra/.intgd/config/
cp -r "$BACKUP_DIR/keyring-test/" /home/integra/.intgd/

# Fix ownership
sudo chown -R integra:integra /home/integra/.intgd/

# Restart
sudo systemctl start intgd
```

### Export Genesis

Useful before chain upgrades or for debugging.

```bash
# Export current state as genesis
intgd export --home /home/integra/.intgd > exported_genesis.json

# Export at a specific height
intgd export --height <block_height> --home /home/integra/.intgd > exported_genesis_at_height.json
```

---

## Upgrade

### Binary Upgrade with Cosmovisor (Recommended)

When a governance proposal schedules a chain upgrade, Cosmovisor handles the binary swap automatically if the new binary is placed in the right directory.

```bash
# 1. Build the new binary
cd /tmp
git clone https://github.com/Integra-layer/evm.git evm-upgrade
cd evm-upgrade/integra
git checkout <new_version_tag_or_commit>

CGO_ENABLED=1 go build -tags "netgo" \
  -ldflags "-w -s \
    -X github.com/cosmos/cosmos-sdk/version.Name=integra \
    -X github.com/cosmos/cosmos-sdk/version.AppName=intgd" \
  -trimpath -o intgd ./cmd/intgd

# 2. Place it in the Cosmovisor upgrades directory
# The upgrade name must match the on-chain proposal name exactly
UPGRADE_NAME="<upgrade-name-from-proposal>"
mkdir -p /home/integra/.intgd/cosmovisor/upgrades/$UPGRADE_NAME/bin
cp intgd /home/integra/.intgd/cosmovisor/upgrades/$UPGRADE_NAME/bin/intgd
chmod +x /home/integra/.intgd/cosmovisor/upgrades/$UPGRADE_NAME/bin/intgd
sudo chown -R integra:integra /home/integra/.intgd/cosmovisor/

# 3. Cosmovisor will automatically switch at the upgrade height
# Monitor logs:
journalctl -u intgd -f --no-hostname
```

> **Cross-reference**: See `references/cosmovisor-setup.md` for Cosmovisor installation and configuration.

### Manual Binary Upgrade (Without Cosmovisor)

```bash
# 1. Build the new binary (same as above)
cd /tmp
git clone https://github.com/Integra-layer/evm.git evm-upgrade
cd evm-upgrade/integra
git checkout <new_version_tag_or_commit>

CGO_ENABLED=1 go build -tags "netgo" \
  -ldflags "-w -s \
    -X github.com/cosmos/cosmos-sdk/version.Name=integra \
    -X github.com/cosmos/cosmos-sdk/version.AppName=intgd" \
  -trimpath -o intgd ./cmd/intgd

# 2. Wait for the chain to halt at upgrade height
# Watch logs for: "UPGRADE "<name>" NEEDED at height: <height>"
journalctl -u intgd -f --no-hostname

# 3. Once halted, replace the binary
sudo systemctl stop intgd
sudo cp intgd /usr/local/bin/intgd
sudo chmod +x /usr/local/bin/intgd

# 4. Verify version
intgd version

# 5. Restart
sudo systemctl start intgd
journalctl -u intgd -f --no-hostname
```

> **Timing**: The chain halts at the upgrade height. All validators must upgrade before the chain can resume. Act quickly to avoid missing blocks.

### Rollback if Needed

If the upgrade fails and the chain needs to roll back:

```bash
# Stop the node
sudo systemctl stop intgd

# Restore the old binary
sudo cp /path/to/old/intgd /usr/local/bin/intgd

# Roll back the last state change (if applicable)
intgd rollback --home /home/integra/.intgd

# Restart
sudo systemctl start intgd
```

> **Note**: Rollback is only possible if the chain has not progressed past the upgrade height. Coordinate with other validators.

---

## Dangerous Operations

> **WARNING**: The operations in this section can cause data loss or extended downtime. Use with extreme caution. Back up keys before proceeding.

### Reset Chain State

Wipes all chain data but preserves keys and configuration. The node will need to re-sync from genesis or a snapshot.

```bash
# Stop the node first
sudo systemctl stop intgd

# Back up keys (mandatory before reset)
cp /home/integra/.intgd/config/priv_validator_key.json /tmp/priv_validator_key.json.bak
cp /home/integra/.intgd/config/node_key.json /tmp/node_key.json.bak
cp -r /home/integra/.intgd/keyring-test/ /tmp/keyring-test-bak/

# Reset all chain data
intgd comet unsafe-reset-all --home /home/integra/.intgd

# Verify keys are still intact
ls -la /home/integra/.intgd/config/priv_validator_key.json
ls -la /home/integra/.intgd/config/node_key.json

# Restart (node will begin syncing from genesis)
sudo systemctl start intgd
```

### Re-sync from Scratch

Full wipe and re-initialization. Use when chain data is corrupted beyond repair.

```bash
# Stop the node
sudo systemctl stop intgd

# Back up EVERYTHING critical
BACKUP="/tmp/integra-emergency-backup-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"
cp /home/integra/.intgd/config/priv_validator_key.json "$BACKUP/"
cp /home/integra/.intgd/config/node_key.json "$BACKUP/"
cp -r /home/integra/.intgd/keyring-test/ "$BACKUP/"
echo "Backup saved to: $BACKUP"

# Remove all data
rm -rf /home/integra/.intgd/data

# Re-download genesis
# --- Mainnet ---
curl -sL https://rpc.integralayer.com/genesis | jq '.result.genesis' > /home/integra/.intgd/config/genesis.json

# --- Testnet ---
# curl -sL https://ormos.integralayer.com/cometbft/genesis | jq '.result.genesis' > /home/integra/.intgd/config/genesis.json

# Verify genesis chain_id
jq '.chain_id' /home/integra/.intgd/config/genesis.json

# Fix ownership
sudo chown -R integra:integra /home/integra/.intgd/

# Restart
sudo systemctl start intgd
journalctl -u intgd -f --no-hostname
```

> **Note**: Full re-sync from genesis can take days. If state sync snapshots are available, consider using state sync for faster recovery. Check `references/network-config.md` for snapshot providers.

---

## Quick Reference: Common Command Patterns

All transaction commands follow this pattern:

```bash
intgd tx <module> <action> [args] \
  --from=$KEY_NAME \
  --chain-id=integra-1 \          # or integra-testnet-1 for testnet
  --gas=auto \
  --gas-adjustment=1.5 \
  --gas-prices=1000000000airl \    # REQUIRED
  --keyring-backend=test \
  --home=$HOME \
  -y
```

All query commands follow this pattern:

```bash
intgd query <module> <action> [args] --home $HOME
```

### Token Conversion Reference

| IRL | airl |
|-----|------|
| 1 IRL | `1000000000000000000` airl |
| 10 IRL | `10000000000000000000` airl |
| 100 IRL | `100000000000000000000` airl |
| 0.1 IRL | `100000000000000000` airl |
| 0.01 IRL | `10000000000000000` airl |

> **CRITICAL**: The token is **IRL** / **airl** (NOT ILR/ailr). 18 decimal places, same as ETH wei.

---

## Troubleshooting

> **Cross-reference**: See `references/troubleshooting.md` for the full troubleshooting guide.

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `catching_up: true` for a long time | Few peers or slow network | Check peer count, add more persistent peers |
| Node not signing blocks | Validator jailed or not in active set | Check signing-info, unjail if needed |
| `account sequence mismatch` on tx | Pending tx or wrong sequence | Wait for pending tx to confirm, or query account sequence |
| `insufficient funds` on tx | Not enough airl for amount + gas | Check balance, reduce amount or fund the account |
| `validator does not exist` | Wrong valoper address or not created | Verify valoper address with `keys show --bech val` |
| No peers connecting | Missing `--chain-id` on `intgd start` | Verify systemd unit has `--chain-id integra-1` flag |
| `AppHash mismatch` | Wrong binary version | Rebuild intgd from `Integra-layer/evm` at correct commit |
| Commission change rejected | Exceeds max-change-rate or too frequent | Can only change once per 24h, within max-change-rate bounds |
| Tombstoned | Double-signed (ran same key on 2 nodes) | Permanent -- must create a new validator with a new key |
