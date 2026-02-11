#!/bin/bash
set -e

CHAIN_ID="${CHAIN_ID:-integra-1}"
MONIKER="${MONIKER:-my-integra-validator}"
HOME_DIR="/root/.intgd"
MIN_GAS_PRICES="${MIN_GAS_PRICES:-0airl}"

# Select RPC endpoint based on network
if [ "$CHAIN_ID" = "integra-1" ]; then
    RPC="https://rpc.integralayer.com"
elif [ "$CHAIN_ID" = "ormos-1" ]; then
    RPC="https://testnet-rpc.integralayer.com"
else
    echo "ERROR: Unknown CHAIN_ID '$CHAIN_ID'. Use 'integra-1' (mainnet) or 'ormos-1' (testnet)."
    exit 1
fi

# Initialize if not already done
if [ ! -f "$HOME_DIR/config/config.toml" ]; then
    echo "==> Initializing node with moniker: $MONIKER, chain-id: $CHAIN_ID"
    intgd init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR"

    # Download unmodified genesis from RPC (hash must match network exactly)
    echo "==> Downloading genesis from $RPC ..."
    curl -sf "$RPC/genesis" | jq '.result.genesis' > "$HOME_DIR/config/genesis.json"
    echo "==> Genesis downloaded (initial_height=$(jq -r .initial_height "$HOME_DIR/config/genesis.json"))"

    # Auto-discover persistent peers from network
    echo "==> Discovering persistent peers..."
    PEERS="$(curl -sf "$RPC/net_info" | jq -r '.result.peers[] | .node_info.id + "@" + .remote_ip + ":26656"' | head -5 | paste -sd, || true)"
    if [ -n "$PEERS" ]; then
        sed -i "s/persistent_peers = \"\"/persistent_peers = \"$PEERS\"/" "$HOME_DIR/config/config.toml"
        echo "==> Peers set: $PEERS"
    else
        echo "==> Warning: Could not auto-discover peers. Set PEERS env var or edit config.toml manually."
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

    echo "==> Initialization complete!"
fi

# CRITICAL: --chain-id flag is required for CometBFT handshake with peers
echo "==> Starting intgd node (chain-id: $CHAIN_ID)..."
exec intgd start --home "$HOME_DIR" --chain-id "$CHAIN_ID"
