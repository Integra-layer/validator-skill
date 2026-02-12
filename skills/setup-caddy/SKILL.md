---
name: setup-caddy
description: Set up Caddy as an HTTPS reverse proxy for validator RPC endpoints
---

# Set Up Caddy HTTPS Reverse Proxy for Validator Endpoints

Configure Caddy as an automatic HTTPS reverse proxy in front of the Integralayer validator's RPC endpoints, providing TLS termination, CORS headers, and WebSocket support.

## Prerequisites

- A domain name with a DNS A record pointing to the validator server's public IP
- Ports 80 and 443 open in the firewall (required for Let's Encrypt ACME challenge)
- The validator node running with RPC endpoints on localhost
- Ubuntu 22.04+ or Debian 12+

## Architecture Overview

```
[Internet]
    │
    ▼ HTTPS (:443)
[Caddy]
    ├── /rpc       → localhost:8545  (EVM JSON-RPC)
    ├── /ws        → localhost:8546  (EVM WebSocket)
    ├── /cometbft  → localhost:26657 (CometBFT RPC)
    ├── /cometbft/* → localhost:26657
    ├── /rest      → localhost:1317  (Cosmos REST API)
    └── /rest/*    → localhost:1317
```

Caddy automatically provisions and renews TLS certificates via Let's Encrypt. No manual certificate management is needed.

## Step 1: Install Caddy

### Via apt (Recommended)

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

### Via Docker (Alternative)

```bash
docker pull caddy:2
```

If using Docker, mount the Caddyfile and data volumes:

```bash
docker run -d --name caddy \
  --network host \
  -v /etc/caddy/Caddyfile:/etc/caddy/Caddyfile \
  -v caddy_data:/data \
  -v caddy_config:/config \
  caddy:2
```

## Step 2: Open Firewall Ports

Caddy needs ports 80 (HTTP, for ACME challenge) and 443 (HTTPS):

```bash
sudo ufw allow 80/tcp comment "Caddy HTTP (ACME challenge)"
sudo ufw allow 443/tcp comment "Caddy HTTPS"
```

> **Important**: Once Caddy is proxying the RPC endpoints over HTTPS, you can close the direct RPC ports (8545, 8546, 26657, 1317) from public access if they were previously open. Keep them listening on localhost only.

## Step 3: Configure the Caddyfile

Use the template at `templates/caddy/Caddyfile` or create `/etc/caddy/Caddyfile` with the following configuration:

```caddyfile
yourdomain.com {
    # ── EVM JSON-RPC (HTTP) ──────────────────────────────
    handle /rpc {
        reverse_proxy localhost:8545
    }

    # ── EVM WebSocket ────────────────────────────────────
    handle /ws {
        reverse_proxy localhost:8546 {
            # Strip Origin header — required for EVM WebSocket to accept connections
            header_up -Origin
        }
    }

    # ── CometBFT RPC ────────────────────────────────────
    handle /cometbft {
        reverse_proxy localhost:26657
    }
    handle /cometbft/* {
        uri strip_prefix /cometbft
        reverse_proxy localhost:26657
    }

    # ── Cosmos REST API ──────────────────────────────────
    handle /rest {
        reverse_proxy localhost:1317
    }
    handle /rest/* {
        uri strip_prefix /rest
        reverse_proxy localhost:1317
    }

    # ── CORS Headers ────────────────────────────────────
    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Authorization"
        Access-Control-Max-Age 3600
    }

    # ── Logging ──────────────────────────────────────────
    log {
        output file /var/log/caddy/access.log {
            roll_size 100mb
            roll_keep 5
            roll_keep_for 720h
        }
        format json
    }
}
```

Replace `yourdomain.com` with your actual domain (e.g., `adamboudj.integralayer.com`).

### Key Configuration Notes

- **`header_up -Origin`**: The EVM WebSocket endpoint rejects connections with an `Origin` header that does not match `localhost`. Stripping the header allows browser-based dApps to connect.
- **`uri strip_prefix`**: Removes the path prefix before forwarding to the backend. For example, `/cometbft/status` becomes `/status` when forwarded to port 26657.
- **CORS `*`**: Allows any origin. For production, restrict to specific domains if your endpoints are not intended to be fully public.

## Step 4: Start Caddy

```bash
# Start and enable Caddy
sudo systemctl start caddy
sudo systemctl enable caddy

# Check status
sudo systemctl status caddy
```

Caddy will automatically:
1. Listen on ports 80 and 443
2. Obtain a TLS certificate from Let's Encrypt for your domain
3. Redirect all HTTP traffic to HTTPS
4. Begin proxying requests to backend endpoints

### Check Caddy Logs

```bash
# Systemd logs
journalctl -u caddy -f --no-hostname

# Access logs (if configured)
tail -f /var/log/caddy/access.log | jq .
```

## Step 5: Verify HTTPS Endpoints

### Test EVM JSON-RPC

```bash
curl -s https://yourdomain.com/rpc \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq .
```

Expected response:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0x6669"
}
```

(`0x6669` = 26217 in hex for mainnet, `0x666a` = 26218 for testnet)

### Test EVM WebSocket

```bash
# Install wscat if needed: npm install -g wscat
wscat -c wss://yourdomain.com/ws
```

Once connected, send:

```json
{"jsonrpc":"2.0","method":"eth_subscribe","params":["newHeads"],"id":1}
```

You should receive new block headers in real time.

### Test CometBFT RPC

```bash
# Node status
curl -s https://yourdomain.com/cometbft/status | jq '.result.sync_info.latest_block_height'

# Net info
curl -s https://yourdomain.com/cometbft/net_info | jq '.result.n_peers'
```

### Test REST API

```bash
# Latest block
curl -s https://yourdomain.com/rest/cosmos/base/tendermint/v1beta1/blocks/latest | jq '.block.header.height'

# Validator set
curl -s https://yourdomain.com/rest/cosmos/staking/v1beta1/validators | jq '.validators | length'
```

## Important Notes

### TLS Certificates

Caddy automatically provisions TLS certificates from Let's Encrypt using the ACME protocol. Requirements:
- Port 80 must be reachable from the internet (for HTTP-01 challenge)
- The DNS A record must resolve to the server's public IP
- Certificates auto-renew before expiration (no cron jobs needed)

### WebSocket Connections

The `/ws` endpoint requires special handling:
- The `header_up -Origin` directive strips the Origin header, which the EVM WebSocket server uses to validate connections
- Without this directive, browser-based dApps will receive connection rejections
- Caddy automatically handles the HTTP-to-WebSocket upgrade (`Connection: Upgrade` and `Upgrade: websocket` headers)

### Rate Limiting

For public-facing endpoints, consider adding rate limiting to prevent abuse:

```caddyfile
yourdomain.com {
    # Rate limit: 100 requests per second per IP
    rate_limit {
        zone dynamic_zone {
            key {remote_host}
            events 100
            window 1s
        }
    }

    # ... rest of config
}
```

> **Note**: The `rate_limit` directive requires the Caddy rate-limit plugin. Install it with `xcaddy build --with github.com/mholt/caddy-ratelimit` or use the Docker image that includes it. See `references/security-hardening.md` for DDoS protection strategies.

### Restrict CORS for Production

If endpoints are not meant to be fully public, restrict CORS to known origins:

```caddyfile
header {
    Access-Control-Allow-Origin "https://app.yourdomain.com"
    Access-Control-Allow-Methods "GET, POST, OPTIONS"
    Access-Control-Allow-Headers "Content-Type, Authorization"
}
```

### Lock Down Backend Ports

Once Caddy is handling all external traffic, restrict backend ports to localhost only:

In `~/.intgd/config/config.toml`:

```toml
[rpc]
laddr = "tcp://127.0.0.1:26657"
```

In `~/.intgd/config/app.toml`:

```toml
[json-rpc]
address = "127.0.0.1:8545"
ws-address = "127.0.0.1:8546"

[api]
address = "tcp://127.0.0.1:1317"
```

Then remove the public firewall rules for those ports:

```bash
sudo ufw delete allow 8545/tcp
sudo ufw delete allow 8546/tcp
sudo ufw delete allow 26657/tcp
sudo ufw delete allow 1317/tcp
```

## MetaMask Configuration (via Caddy Proxy)

| Setting | Value |
|---------|-------|
| Network Name | Integralayer |
| RPC URL | `https://yourdomain.com/rpc` |
| Chain ID | `26217` (mainnet) or `26218` (testnet) |
| Currency Symbol | IRL |
| Block Explorer URL | `https://explorer.integralayer.com` |

## Troubleshooting

- **Certificate not provisioning**: Ensure port 80 is open and the DNS A record points to the server. Check `journalctl -u caddy` for ACME errors.
- **WebSocket connection refused**: Verify `header_up -Origin` is in the `/ws` handler. Check that the EVM WebSocket is running on port 8546 (`curl http://localhost:8546`).
- **502 Bad Gateway**: The backend service is not running or not listening on the expected port. Check with `ss -tlnp | grep <port>`.
- **CORS errors in browser**: Verify the CORS headers are set in the Caddyfile. Use browser developer tools (Network tab) to inspect the `Access-Control-Allow-Origin` response header.
- **Rate limiting not working**: The rate-limit module is a plugin, not built into standard Caddy. Build a custom Caddy binary with `xcaddy` or use an alternative rate-limiting approach.

## Related References

- `references/security-hardening.md` -- Rate limiting and DDoS protection
- `references/network-config.md` -- Port reference and backend configuration
- `templates/caddy/Caddyfile` -- Template Caddyfile
