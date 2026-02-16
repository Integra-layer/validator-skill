# Integralayer Validator Troubleshooting Guide

Consolidated troubleshooting reference for common issues when running an Integralayer validator or full node.

## EVM Chain ID Wrong (262144 Instead of 26217)

**Symptom**: EVM transactions fail, MetaMask cannot connect, or EVM RPC returns wrong chain ID.

**Cause**: `intgd init` sets a default EVM chain ID of `262144`, which is incorrect.

**Fix**:

```bash
# Edit app.toml
nano ~/.intgd/config/app.toml

# Find the [evm] section and change:
evm-chain-id = "26217"    # mainnet
# evm-chain-id = "26218"  # testnet

# Restart node
sudo systemctl restart intgd
```

**Verify**:

```bash
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq
# Should return 0x6669 (26217) for mainnet
```

## Token Denom Confusion (IRL/airl NOT ILR/ailr)

**Symptom**: Transactions fail with "unknown denom" or "insufficient funds" despite having balance.

**Cause**: The token is IRL (smallest unit: `airl`), not ILR/`ailr`.

**Fix**: Use the correct denom in all commands:

```bash
# Correct
intgd tx bank send <from> <to> 1000000000000000000airl --chain-id integra-1

# Wrong -- will fail
intgd tx bank send <from> <to> 1000000000000000000ailr --chain-id integra-1
```

1 IRL = 1,000,000,000,000,000,000 airl (10^18 airl, same as ETH/wei).

## CometBFT Handshake Failure / No Peers

**Symptom**: Node starts but shows "no peers" or handshake failures. Logs show connection attempts that immediately fail.

**Possible Causes**:

1. **Wrong or missing persistent peers**:
   ```bash
   # Check config
   grep persistent_peers ~/.intgd/config/config.toml

   # Format must be: <node_id>@<ip>:<port>
   # Get node ID from a peer
   curl -s http://165.227.118.77:26657/status | jq -r '.result.node_info.id'
   ```

2. **Firewall blocking port 26656**:
   ```bash
   # Check if port is open
   sudo ufw status
   # Allow P2P
   sudo ufw allow 26656/tcp
   ```

3. **Wrong chain-id in genesis**:
   ```bash
   # Verify genesis chain ID
   jq '.chain_id' ~/.intgd/config/genesis.json
   # Should return "integra-1" (mainnet) or "integra-testnet-1" (testnet)
   ```

4. **Clock skew**: CometBFT requires roughly synchronized time.
   ```bash
   # Check time
   timedatectl status
   # Enable NTP
   sudo timedatectl set-ntp true
   ```

## AppHash Mismatch

**Symptom**: Node halts with `wrong Block.Header.AppHash` error.

**Cause**: The binary version does not match what the chain expects at a given height. This almost always means you are running the wrong binary.

**Critical**: The `intgd` binary MUST be built from the **Integra-layer/evm** repository, NOT from chain-core or any fork.

**Fix**:

```bash
# 1. Stop the node
sudo systemctl stop intgd

# 2. Build the correct binary
cd ~/evm
git fetch --all --tags
git checkout <correct-tag>
make install

# 3. Verify
intgd version

# 4. If state is corrupted, you may need to reset
intgd tendermint unsafe-reset-all --keep-addr-book

# 5. Re-download genesis if needed and resync
# Or restore from a snapshot

# 6. Restart
sudo systemctl start intgd
```

## Genesis Hash Mismatch

**Symptom**: Node fails to start with "genesis hash mismatch" error.

**Cause**: Your `genesis.json` does not match the network's expected genesis.

**Fix**:

```bash
# Re-download genesis
curl -L https://rpc.integralayer.com/genesis | jq '.result.genesis' > ~/.intgd/config/genesis.json

# Verify hash
sha256sum ~/.intgd/config/genesis.json

# Reset state (keep address book)
intgd tendermint unsafe-reset-all --keep-addr-book

# Restart
sudo systemctl restart intgd
```

## Connection Refused on Various Ports

**Symptom**: `curl: (7) Failed to connect to localhost port XXXX: Connection refused`

**Check each port's binding**:

| Port | Config File | Setting |
|---|---|---|
| 26657 (RPC) | config.toml | `[rpc] laddr` |
| 8545 (EVM HTTP) | app.toml | `[json-rpc] address` |
| 8546 (EVM WS) | app.toml | `[json-rpc] ws-address` |
| 1317 (REST) | app.toml | `[api] address` + `enable = true` |
| 9090 (gRPC) | app.toml | `[grpc] address` + `enable = true` |

```bash
# Check if the service is actually bound
ss -tlnp | grep -E '26657|8545|8546|1317|9090'

# Check if the node is running
sudo systemctl status intgd
```

**Common causes**:
- Service not enabled in config (e.g., `enable = false` for API/gRPC)
- Binding to localhost vs 0.0.0.0
- Node hasn't finished starting yet
- Port conflict with another process

## EVM RPC Not Responding

**Symptom**: EVM JSON-RPC calls return errors or time out.

**Checks**:

```bash
# 1. Is JSON-RPC enabled?
grep -A5 '\[json-rpc\]' ~/.intgd/config/app.toml
# Ensure: enable = true

# 2. Is it binding correctly?
# address = "0.0.0.0:8545" for external access
# address = "127.0.0.1:8545" for localhost only

# 3. Is the node synced?
intgd status | jq '.SyncInfo.catching_up'
# Must be false for EVM RPC to work properly

# 4. Test locally
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq

# 5. Check EVM chain ID is correct
# Wrong chain ID (262144) can cause unexpected EVM behavior
grep evm-chain-id ~/.intgd/config/app.toml
```

## Validator Jailed

**Symptom**: Validator is no longer signing blocks, status shows "jailed".

**Cause**: Missing too many blocks (downtime) or double signing.

**Check status**:

```bash
# Check if jailed
intgd query staking validator <validator_operator_address> | grep jailed

# Check signing info (missed blocks, tombstoned status)
intgd query slashing signing-info $(intgd tendermint show-validator)
```

**Unjail** (only works for downtime, NOT for double signing):

```bash
# Wait until the jail period has passed (check signing-info for jail_until)
intgd tx slashing unjail \
  --from <key_name> \
  --chain-id integra-1 \
  --gas auto \
  --gas-adjustment 1.5 \
  --gas-prices 0.0001airl
```

**If tombstoned**: The validator was caught double signing. This is permanent and cannot be undone. You must create a new validator with a new key.

## Out of Memory (OOM)

**Symptom**: Node process killed, `dmesg` shows OOM killer.

**Checks and Fixes**:

```bash
# Check available memory
free -h

# Check if OOM killed the process
dmesg | grep -i "oom\|killed process"

# Add swap if needed
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# Make permanent:
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**Recommended**: Use at least 8GB RAM (m6i.xlarge has 16GB). If consistently running out, upgrade the instance.

**Tune CometBFT**:
```toml
# In config.toml, reduce cache sizes if needed
[mempool]
size = 5000        # Default 5000, reduce if needed
cache_size = 10000 # Default 10000
```

## Disk Full

**Symptom**: Node crashes, writes fail, logs show "no space left on device".

**Checks and Fixes**:

```bash
# Check disk usage
df -h

# Find large directories
du -sh ~/.intgd/data/*

# Pruning: configure in app.toml
# For validators, "default" or "nothing" is recommended
# For non-archival nodes, "everything" saves space
```

```toml
# app.toml pruning options
pruning = "default"            # keep recent + every 500th
# pruning = "everything"       # keep only latest (not for validators)
# pruning = "nothing"          # archival node (most disk)
# pruning = "custom"
# pruning-keep-recent = "100"
# pruning-interval = "10"
```

```bash
# If pruning alone isn't enough, compact the database
intgd tendermint compact-goleveldb

# Consider expanding the EBS volume (see aws-deployment-notes.md)
```

## Node Stuck Syncing

**Symptom**: `catching_up: true` and block height not advancing, or advancing very slowly.

**Checks**:

```bash
# Check sync status
intgd status | jq '.SyncInfo'

# Compare with network height
curl -s https://rpc.integralayer.com/status | jq '.result.sync_info.latest_block_height'

# Check peer count
curl -s http://localhost:26657/net_info | jq '.result.n_peers'
```

**Fixes**:

1. **Not enough peers**: Add more persistent peers or seeds
2. **State sync**: For a fresh node, state sync is much faster than syncing from genesis:
   ```toml
   # config.toml
   [statesync]
   enable = true
   rpc_servers = "https://rpc.integralayer.com:443,https://rpc.integralayer.com:443"
   trust_height = <recent_height>
   trust_hash = "<hash_at_trust_height>"
   trust_period = "168h"
   ```
3. **Snapshot restore**: Download a recent snapshot from the community and restore it
4. **Resource bottleneck**: Check CPU, RAM, and disk I/O with `htop` and `iostat`

## "wrong Block.Header.AppHash" After Upgrade

**Symptom**: After a chain upgrade, the node fails with AppHash mismatch.

**Cause**: The new binary was not placed correctly, or the wrong version was used.

**Fix**:

```bash
# 1. Stop the node
sudo systemctl stop intgd

# 2. Verify the binary version
intgd version --long

# 3. Check the upgrade plan
intgd query upgrade plan

# 4. Ensure the binary matches what the upgrade requires
# Rebuild from the correct tag if needed
cd ~/evm
git fetch --all --tags
git checkout <upgrade-tag>
make install

# 5. If using Cosmovisor, check the upgrade directory
ls -la ~/.intgd/cosmovisor/upgrades/<upgrade-name>/bin/intgd

# 6. If state is corrupted, restore from a pre-upgrade backup
# or resync from a snapshot

# 7. Restart
sudo systemctl start intgd
```

## Docker-Specific Issues

### Container Restart Loops

**Symptom**: Container repeatedly starts and crashes.

```bash
# Check logs
docker logs <container_name> --tail 100

# Common causes:
# - Wrong genesis file
# - Missing or wrong config
# - Permission issues on mounted volumes
# - Port conflicts
```

### Volume Permissions

**Symptom**: Node fails with permission denied errors on data directory.

```bash
# Check the UID/GID inside the container
docker exec <container_name> id

# Fix ownership on the host volume
sudo chown -R 1000:1000 /path/to/intgd-data

# Or run the container with matching user
docker run --user $(id -u):$(id -g) ...
```

### Container Networking

```bash
# Ensure ports are mapped correctly
docker run -p 26656:26656 -p 26657:26657 -p 8545:8545 ...

# For P2P, the external address must be set
# In config.toml:
external_address = "<your_public_ip>:26656"
```

## Quick Diagnostic Commands

```bash
# Overall node status
intgd status | jq

# Check if synced
intgd status | jq '.SyncInfo.catching_up'

# Latest block height and time
intgd status | jq '{height: .SyncInfo.latest_block_height, time: .SyncInfo.latest_block_time}'

# Peer count
curl -s http://localhost:26657/net_info | jq '.result.n_peers'

# Validator signing status
intgd query slashing signing-info $(intgd tendermint show-validator) --chain-id integra-1

# Check validator in active set
intgd query staking validators --status bonded --chain-id integra-1 | grep -A5 <your_moniker>

# Memory usage
ps aux | grep intgd | grep -v grep

# Disk usage
du -sh ~/.intgd/data/

# Check systemd service
sudo systemctl status intgd
journalctl -u intgd --since "1 hour ago" --no-pager | tail -50

# EVM health check
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq
```

## When to Seek Help

- **Tombstoned validator**: Cannot be unjailed; needs community guidance on next steps
- **Persistent AppHash mismatches**: May indicate a chain-level issue; check Discord/governance
- **Consensus failure**: If multiple validators halt simultaneously, this is a network event
- **Unknown errors in EVM layer**: Check the Integra-layer/evm GitHub issues
