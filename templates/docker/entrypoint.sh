#!/bin/bash
set -e

CHAIN_ID="${CHAIN_ID:-integra-1}"
MONIKER="${MONIKER:-my-integra-validator}"
HOME_DIR="/root/.intgd"
STATE_SYNC="${STATE_SYNC:-true}"
FORCE_INIT="${FORCE_INIT:-false}"
AUTO_HEAL="${AUTO_HEAL:-true}"
SNAPSHOT_INTERVAL="${SNAPSHOT_INTERVAL:-1000}"

# Set sensible gas price defaults per network
if [ "$CHAIN_ID" = "integra-1" ]; then
    MIN_GAS_PRICES="${MIN_GAS_PRICES:-0airl}"
elif [ "$CHAIN_ID" = "integra-testnet-1" ]; then
    # Testnet enforces minimum 1 gwei — 0airl transactions will be rejected
    MIN_GAS_PRICES="${MIN_GAS_PRICES:-1000000000airl}"
fi

# Select RPC endpoint based on network
# RPC = path-based proxy for genesis/peer queries (supports /genesis, /net_info, etc.)
# STATE_SYNC_RPC = direct host:port for CometBFT state sync light client (no path prefix)
if [ "$CHAIN_ID" = "integra-1" ]; then
    RPC="https://rpc.integralayer.com"
    STATE_SYNC_RPC="https://rpc.integralayer.com:443,http://3.92.110.107:26657"
    EVM_CHAIN_ID=26217
elif [ "$CHAIN_ID" = "integra-testnet-1" ]; then
    RPC="https://ormos.integralayer.com/cometbft"
    STATE_SYNC_RPC="http://13.218.88.209:26657,http://167.71.173.21:26657,http://143.198.25.105:26657"
    EVM_CHAIN_ID=26218
else
    echo "ERROR: Unknown CHAIN_ID '$CHAIN_ID'. Use 'integra-1' (mainnet) or 'integra-testnet-1' (testnet)."
    exit 1
fi

# ─── Helper: find a working RPC endpoint ─────────────────────────────────────
find_working_rpc() {
    local IFS=','
    for rpc in $STATE_SYNC_RPC; do
        rpc=$(echo "$rpc" | xargs)  # trim whitespace
        if curl -sf --max-time 5 "$rpc/status" > /dev/null 2>&1; then
            echo "$rpc"
            return 0
        fi
    done
    # Fallback to primary RPC
    if curl -sf --max-time 5 "$RPC/status" > /dev/null 2>&1; then
        echo "$RPC"
        return 0
    fi
    return 1
}

# ─── Helper: configure state sync in config.toml ─────────────────────────────
configure_state_sync() {
    local WORKING_RPC
    WORKING_RPC=$(find_working_rpc) || {
        echo "==> Warning: No reachable RPC found. Disabling state sync."
        return 1
    }
    echo "==> Using RPC: $WORKING_RPC for state sync configuration"

    LATEST_HEIGHT=$(curl -sf --max-time 15 "$WORKING_RPC/status" | jq -r '.result.sync_info.latest_block_height' || echo "")
    if [ -z "$LATEST_HEIGHT" ] || [ "$LATEST_HEIGHT" = "null" ]; then
        echo "==> Warning: Could not fetch latest block height. Disabling state sync."
        return 1
    fi

    # Align trust height to snapshot interval boundary (snapshots are every $SNAPSHOT_INTERVAL blocks)
    TRUST_HEIGHT=$(( (LATEST_HEIGHT / SNAPSHOT_INTERVAL - 2) * SNAPSHOT_INTERVAL ))
    if [ "$TRUST_HEIGHT" -lt 1 ]; then
        echo "==> Warning: Chain too young for state sync (height=$LATEST_HEIGHT). Falling back to block replay."
        return 1
    fi

    TRUST_HASH=$(curl -sf --max-time 15 "$WORKING_RPC/block?height=$TRUST_HEIGHT" | jq -r '.result.block_id.hash' || echo "")
    if [ -z "$TRUST_HASH" ] || [ "$TRUST_HASH" = "null" ]; then
        echo "==> Warning: Could not fetch trust hash at height $TRUST_HEIGHT. Disabling state sync."
        return 1
    fi

    sed -i 's/enable = false/enable = true/' "$HOME_DIR/config/config.toml"
    # Handle both empty and pre-existing rpc_servers
    sed -i "s|rpc_servers = \".*\"|rpc_servers = \"${STATE_SYNC_RPC}\"|" "$HOME_DIR/config/config.toml"
    sed -i "s/trust_height = .*/trust_height = $TRUST_HEIGHT/" "$HOME_DIR/config/config.toml"
    sed -i "s/trust_hash = \".*\"/trust_hash = \"$TRUST_HASH\"/" "$HOME_DIR/config/config.toml"
    sed -i 's/trust_period = "168h0m0s"/trust_period = "336h0m0s"/' "$HOME_DIR/config/config.toml"
    echo "==> State sync enabled (trust_height=$TRUST_HEIGHT, trust_hash=$TRUST_HASH)"
    return 0
}

# ─── Auto-heal: detect stale chain and re-sync ───────────────────────────────
if [ "$AUTO_HEAL" = "true" ] && [ -f "$HOME_DIR/data/priv_validator_state.json" ]; then
    # Node has existing data — check if it's stale
    STALE_THRESHOLD=600  # 10 minutes with no new blocks = stale

    LOCAL_STATUS=$(curl -sf --max-time 5 http://localhost:26657/status 2>/dev/null || echo "")
    if [ -n "$LOCAL_STATUS" ]; then
        BLOCK_TIME=$(echo "$LOCAL_STATUS" | jq -r '.result.sync_info.latest_block_time' 2>/dev/null || echo "")
    else
        # Node not running yet — check priv_validator_state for last signed height
        LAST_HEIGHT=$(jq -r '.height' "$HOME_DIR/data/priv_validator_state.json" 2>/dev/null || echo "0")
        # Try to get block time from a working RPC
        WORKING_RPC=$(find_working_rpc 2>/dev/null || echo "")
        if [ -n "$WORKING_RPC" ] && [ "$LAST_HEIGHT" != "0" ]; then
            REMOTE_HEIGHT=$(curl -sf --max-time 10 "$WORKING_RPC/status" | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo "0")
            REMOTE_TIME=$(curl -sf --max-time 10 "$WORKING_RPC/status" | jq -r '.result.sync_info.latest_block_time' 2>/dev/null || echo "")

            if [ -n "$REMOTE_TIME" ] && [ "$REMOTE_TIME" != "null" ]; then
                REMOTE_EPOCH=$(date -d "$REMOTE_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${REMOTE_TIME%%.*}" +%s 2>/dev/null || echo "0")
                NOW_EPOCH=$(date +%s)
                BLOCK_AGE=$((NOW_EPOCH - REMOTE_EPOCH))
                HEIGHT_DIFF=$((REMOTE_HEIGHT - LAST_HEIGHT))

                if [ "$BLOCK_AGE" -gt "$STALE_THRESHOLD" ]; then
                    echo "==> Chain appears halted (last block ${BLOCK_AGE}s ago). Nothing to heal — waiting for consensus."
                elif [ "$HEIGHT_DIFF" -gt 5000 ]; then
                    echo "==> Node is ${HEIGHT_DIFF} blocks behind. Auto-healing with state sync..."
                    echo "==> Preserving validator keys, resetting data..."
                    # Back up validator state
                    cp "$HOME_DIR/data/priv_validator_state.json" /tmp/priv_validator_state.json.bak
                    intgd tendermint unsafe-reset-all --home "$HOME_DIR" --keep-addr-book
                    # Restore validator state
                    cp /tmp/priv_validator_state.json.bak "$HOME_DIR/data/priv_validator_state.json"
                    # Re-configure state sync with fresh trust height
                    configure_state_sync || echo "==> State sync config failed, will attempt block replay"
                    echo "==> Auto-heal complete. Node will sync on start."
                elif [ "$HEIGHT_DIFF" -gt 0 ]; then
                    echo "==> Node is ${HEIGHT_DIFF} blocks behind (within catch-up range). Will sync normally."
                fi
            fi
        fi
    fi
fi

# Allow re-initialization of a corrupted or stale node
if [ "$FORCE_INIT" = "true" ] && [ -f "$HOME_DIR/config/config.toml" ]; then
    echo "==> FORCE_INIT=true — removing existing configuration for re-initialization..."
    rm -rf "$HOME_DIR/config" "$HOME_DIR/data"
fi

# Initialize if not already done
if [ ! -f "$HOME_DIR/config/config.toml" ]; then
    echo "==> Initializing node with moniker: $MONIKER, chain-id: $CHAIN_ID"
    intgd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR"

    # Download genesis from RPC — fail fast if download or parse fails
    echo "==> Downloading genesis from $RPC ..."
    GENESIS_TMP=$(mktemp)
    if ! curl -sf --max-time 30 "$RPC/genesis" > "$GENESIS_TMP"; then
        echo "ERROR: Failed to download genesis from $RPC/genesis"
        echo "Check network connectivity and RPC endpoint availability."
        rm -f "$GENESIS_TMP"
        exit 1
    fi

    if ! jq -e '.result.genesis.chain_id' "$GENESIS_TMP" > /dev/null 2>&1; then
        echo "ERROR: Downloaded genesis is not valid JSON or missing chain_id."
        echo "The RPC endpoint may be returning an error. Raw response (first 500 chars):"
        head -c 500 "$GENESIS_TMP"
        rm -f "$GENESIS_TMP"
        exit 1
    fi

    jq '.result.genesis' "$GENESIS_TMP" > "$HOME_DIR/config/genesis.json"
    rm -f "$GENESIS_TMP"

    GENESIS_CHAIN_ID=$(jq -r '.chain_id' "$HOME_DIR/config/genesis.json")
    if [ "$GENESIS_CHAIN_ID" != "$CHAIN_ID" ]; then
        echo "ERROR: Genesis chain_id '$GENESIS_CHAIN_ID' does not match CHAIN_ID '$CHAIN_ID'"
        exit 1
    fi
    echo "==> Genesis downloaded (chain_id=$GENESIS_CHAIN_ID, initial_height=$(jq -r .initial_height "$HOME_DIR/config/genesis.json"))"

    # Auto-discover persistent peers from network
    echo "==> Discovering persistent peers..."
    PEERS="$(curl -sf --max-time 15 "$RPC/net_info" | jq -r '.result.peers[] | .node_info.id + "@" + .remote_ip + ":26656"' | head -5 | paste -sd, || true)"
    if [ -n "$PEERS" ]; then
        sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" "$HOME_DIR/config/config.toml"
        echo "==> Peers set: $PEERS"
    else
        echo "==> Warning: Could not auto-discover peers. Set PEERS_OVERRIDE env var or edit config.toml manually."
    fi

    # Override peers if explicitly provided
    if [ -n "${PEERS_OVERRIDE:-}" ]; then
        sed -i "s/persistent_peers = \".*\"/persistent_peers = \"$PEERS_OVERRIDE\"/" "$HOME_DIR/config/config.toml"
        echo "==> Peers overridden: $PEERS_OVERRIDE"
    fi

    # Bind RPC to all interfaces for Docker access
    sed -i 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|' "$HOME_DIR/config/config.toml"

    # Enable EVM JSON-RPC on all interfaces
    sed -i 's/address = "127.0.0.1:8545"/address = "0.0.0.0:8545"/' "$HOME_DIR/config/app.toml" || true
    sed -i 's/ws-address = "127.0.0.1:8546"/ws-address = "0.0.0.0:8546"/' "$HOME_DIR/config/app.toml" || true

    # Set minimum gas prices
    sed -i "s/minimum-gas-prices = \"\"/minimum-gas-prices = \"$MIN_GAS_PRICES\"/" "$HOME_DIR/config/app.toml" || true

    # Fix EVM chain ID (default 262144 is wrong)
    sed -i "s/evm-chain-id = 262144/evm-chain-id = $EVM_CHAIN_ID/" "$HOME_DIR/config/app.toml" || true

    # Enable snapshot serving so this node can help others state-sync
    sed -i "s/snapshot-interval = 0/snapshot-interval = $SNAPSHOT_INTERVAL/" "$HOME_DIR/config/app.toml" || true
    sed -i 's/snapshot-keep-recent = 0/snapshot-keep-recent = 2/' "$HOME_DIR/config/app.toml" || true

    # Configure state sync
    if [ "$STATE_SYNC" = "true" ]; then
        echo "==> Configuring state sync..."
        configure_state_sync || echo "==> Falling back to block replay."
    else
        echo "==> State sync disabled (STATE_SYNC=false). Node will replay all blocks from genesis."
    fi

    echo "==> Initialization complete!"
fi

# CRITICAL: --chain-id flag is required for CometBFT handshake with peers
echo "==> Starting intgd node (chain-id: $CHAIN_ID)..."
exec intgd start --home "$HOME_DIR" --chain-id "$CHAIN_ID"
