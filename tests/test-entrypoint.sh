#!/bin/bash
# Tests for templates/docker/entrypoint.sh
# Mocks intgd and curl to validate entrypoint logic without Docker or network.
# Requires: jq, gsed (brew install gnu-sed) on macOS
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTRYPOINT="$REPO_ROOT/templates/docker/entrypoint.sh"

# Preflight: the entrypoint uses GNU sed -i (no backup arg). On macOS we need gsed.
if [[ "$(uname)" == "Darwin" ]]; then
    if ! command -v gsed &>/dev/null; then
        echo "ERROR: gsed required on macOS (brew install gnu-sed)"
        exit 1
    fi
    GNU_SED="gsed"
else
    GNU_SED="sed"
fi

PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  FAIL: $1"; }
assert_contains() {
    if echo "$1" | grep -qF "$2"; then pass "$3"; else fail "$3 (expected '$2')"; fi
}
assert_file_contains() {
    if grep -qF "$2" "$1" 2>/dev/null; then pass "$3"; else fail "$3 (expected '$2' in $1)"; fi
}

setup() {
    TEST_DIR=$(mktemp -d)
    MOCK_BIN="$TEST_DIR/bin"
    mkdir -p "$MOCK_BIN"

    # Shim: sed → gsed on macOS so the Linux entrypoint works locally
    cat > "$MOCK_BIN/sed" <<SHIM
#!/bin/bash
exec $GNU_SED "\$@"
SHIM
    chmod +x "$MOCK_BIN/sed"

    # Shim: paste — macOS paste doesn't support -sd, use tr instead
    cat > "$MOCK_BIN/paste" << 'SHIM'
#!/bin/bash
if [[ "$1" == "-sd"* ]]; then
    delim="${1#-sd}"
    [ -z "$delim" ] && delim="${2:--}"
    tr '\n' "$delim" | sed "s/${delim}$//"
    echo
else
    /usr/bin/paste "$@"
fi
SHIM
    chmod +x "$MOCK_BIN/paste"

    # Mock intgd
    cat > "$MOCK_BIN/intgd" << 'MOCK'
#!/bin/bash
if [ "$1" = "init" ]; then
    HOME_DIR=""
    while [ $# -gt 0 ]; do
        case "$1" in --home) HOME_DIR="$2"; shift 2 ;; *) shift ;; esac
    done
    [ -z "$HOME_DIR" ] && HOME_DIR="$HOME/.intgd"
    mkdir -p "$HOME_DIR/config" "$HOME_DIR/data"
    cat > "$HOME_DIR/config/config.toml" << 'TOML'
[p2p]
persistent_peers = ""
laddr = "tcp://127.0.0.1:26657"
external_address = ""
[statesync]
enable = false
rpc_servers = ""
trust_height = 0
trust_hash = ""
trust_period = "168h0m0s"
TOML
    cat > "$HOME_DIR/config/app.toml" << 'TOML'
minimum-gas-prices = ""
address = "127.0.0.1:8545"
ws-address = "127.0.0.1:8546"
evm-chain-id = 262144
TOML
    echo '{"initial_height":"1","chain_id":"test"}' > "$HOME_DIR/config/genesis.json"
elif [ "$1" = "start" ]; then
    echo "MOCK_START: $@"
    exit 0
fi
MOCK
    chmod +x "$MOCK_BIN/intgd"

    # Mock curl
    cat > "$MOCK_BIN/curl" << 'MOCK'
#!/bin/bash
URL=""
for arg in "$@"; do
    case "$arg" in http*) URL="$arg" ;; esac
done
case "$URL" in
    */genesis)   echo '{"result":{"genesis":{"initial_height":"1","chain_id":"integra-testnet-1"}}}' ;;
    */net_info)  echo '{"result":{"peers":[{"node_info":{"id":"abc123"},"remote_ip":"10.0.0.1"}]}}' ;;
    */status)    echo '{"result":{"sync_info":{"latest_block_height":"400000"}}}' ;;
    */block*)    echo '{"result":{"block_id":{"hash":"AABBCCDD1122334455667788"}}}' ;;
    *)           echo '{}' ;;
esac
MOCK
    chmod +x "$MOCK_BIN/curl"

    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required to run tests"
        exit 1
    fi

    export PATH="$MOCK_BIN:$PATH"
    export HOME_DIR="$TEST_DIR/intgd-home"
}

teardown() {
    rm -rf "$TEST_DIR"
}

run_entrypoint() {
    (
        export HOME_DIR="$TEST_DIR/intgd-home"
        $GNU_SED "s|HOME_DIR=\"/root/.intgd\"|HOME_DIR=\"$HOME_DIR\"|" "$ENTRYPOINT" | bash
    ) 2>&1
}

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 1: Mainnet chain ID ==="
setup
export CHAIN_ID="integra-1" MONIKER="test-node" STATE_SYNC="false"
OUTPUT=$(run_entrypoint)
assert_contains "$OUTPUT" "chain-id: integra-1" "passes correct chain-id to start"
assert_file_contains "$HOME_DIR/config/app.toml" "evm-chain-id = 26217" "sets mainnet EVM chain ID"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 2: Testnet chain ID ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node" STATE_SYNC="false"
OUTPUT=$(run_entrypoint)
assert_contains "$OUTPUT" "chain-id: integra-testnet-1" "passes correct chain-id to start"
assert_file_contains "$HOME_DIR/config/app.toml" "evm-chain-id = 26218" "sets testnet EVM chain ID"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 3: Unknown chain ID exits with error ==="
setup
export CHAIN_ID="wrong-chain" STATE_SYNC="false"
OUTPUT=$(run_entrypoint 2>&1 || true)
assert_contains "$OUTPUT" "ERROR: Unknown CHAIN_ID" "rejects unknown chain ID"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 4: State sync enabled by default ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node"
unset STATE_SYNC
OUTPUT=$(run_entrypoint)
assert_file_contains "$HOME_DIR/config/config.toml" "enable = true" "state sync enabled in config"
assert_file_contains "$HOME_DIR/config/config.toml" "trust_height = 398000" "trust height set (latest - 2000)"
assert_file_contains "$HOME_DIR/config/config.toml" 'trust_hash = "AABBCCDD1122334455667788"' "trust hash set from RPC"
assert_file_contains "$HOME_DIR/config/config.toml" 'trust_period = "336h0m0s"' "trust period extended"
assert_contains "$OUTPUT" "State sync enabled" "logs state sync activation"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 5: State sync disabled with STATE_SYNC=false ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node" STATE_SYNC="false"
OUTPUT=$(run_entrypoint)
assert_file_contains "$HOME_DIR/config/config.toml" "enable = false" "state sync stays disabled"
assert_file_contains "$HOME_DIR/config/config.toml" "trust_height = 0" "trust height unchanged"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 6: Config fixes applied ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node" STATE_SYNC="false"
run_entrypoint > /dev/null
assert_file_contains "$HOME_DIR/config/config.toml" 'laddr = "tcp://0.0.0.0:26657"' "RPC bound to 0.0.0.0"
assert_file_contains "$HOME_DIR/config/app.toml" 'address = "0.0.0.0:8545"' "EVM RPC bound to 0.0.0.0"
assert_file_contains "$HOME_DIR/config/app.toml" 'ws-address = "0.0.0.0:8546"' "EVM WS bound to 0.0.0.0"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 7: Peer discovery ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node" STATE_SYNC="false"
OUTPUT=$(run_entrypoint)
assert_file_contains "$HOME_DIR/config/config.toml" "abc123@10.0.0.1:26656" "peers discovered and set"
assert_contains "$OUTPUT" "Peers set:" "logs peer discovery"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 8: PEERS_OVERRIDE ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node" STATE_SYNC="false"
export PEERS_OVERRIDE="manual123@1.2.3.4:26656"
OUTPUT=$(run_entrypoint)
assert_file_contains "$HOME_DIR/config/config.toml" "manual123@1.2.3.4:26656" "manual peers override"
assert_contains "$OUTPUT" "Peers overridden:" "logs peer override"
unset PEERS_OVERRIDE
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 9: Skip init if config exists ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node" STATE_SYNC="false"
run_entrypoint > /dev/null
$GNU_SED -i 's/evm-chain-id = 26218/evm-chain-id = 99999/' "$HOME_DIR/config/app.toml"
run_entrypoint > /dev/null
assert_file_contains "$HOME_DIR/config/app.toml" "evm-chain-id = 99999" "second run preserves existing config"
teardown

# ─────────────────────────────────────────────────────────────────────
echo "=== Test 10: State sync fallback when RPC fails ==="
setup
export CHAIN_ID="integra-testnet-1" MONIKER="test-node"
unset STATE_SYNC
cat > "$MOCK_BIN/curl" << 'MOCK'
#!/bin/bash
URL=""
for arg in "$@"; do case "$arg" in http*) URL="$arg" ;; esac; done
case "$URL" in
    */genesis)  echo '{"result":{"genesis":{"initial_height":"1","chain_id":"integra-testnet-1"}}}' ;;
    */net_info) echo '{"result":{"peers":[]}}' ;;
    */status)   echo '{"result":{"sync_info":{"latest_block_height":"400000"}}}' ;;
    */block*)   echo '{"result":{"block_id":{"hash":null}}}' ;;
    *)          echo '{}' ;;
esac
MOCK
chmod +x "$MOCK_BIN/curl"
OUTPUT=$(run_entrypoint)
assert_contains "$OUTPUT" "falling back to block sync" "graceful fallback when RPC fails"
assert_file_contains "$HOME_DIR/config/config.toml" "enable = false" "state sync stays disabled on failure"
teardown

# ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed, $TOTAL total ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
