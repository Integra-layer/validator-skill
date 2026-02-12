# Integralayer Validator Security Hardening

Security best practices for running an Integralayer validator node. Validators hold staked tokens and participate in consensus, so a compromise can lead to slashing, double-signing, and loss of funds.

## Sentry Node Architecture

The recommended production topology places the validator behind one or more sentry nodes. The validator never communicates directly with the public internet for P2P traffic.

```
                  Internet
                     |
          +----------+----------+
          |                     |
     [Sentry A]           [Sentry B]
     (public P2P)         (public P2P)
          |                     |
          +----------+----------+
                     |
              [Validator Node]
              (private network)
```

### Validator config.toml (private)

```toml
[p2p]
# Only connect to sentry nodes
persistent_peers = "<sentry_a_id>@<sentry_a_private_ip>:26656,<sentry_b_id>@<sentry_b_private_ip>:26656"

# Do not advertise validator address
pex = false
addr_book_strict = false
```

### Sentry config.toml (public-facing)

```toml
[p2p]
# Connect to validator and other peers
persistent_peers = "<validator_id>@<validator_private_ip>:26656"

# Hide the validator's node ID from other peers
private_peer_ids = "<validator_node_id>"

# Enable peer exchange for discovery
pex = true
```

### Benefits

- Validator IP is never exposed to the public network
- DDoS attacks target sentries, not the validator
- Sentries can be replaced without affecting the validator
- Multiple sentries provide redundancy

## TMKMS (Tendermint Key Management System)

TMKMS allows you to sign blocks using a Hardware Security Module (HSM) or YubiHSM, keeping your validator's private key off the node entirely.

### Overview

- The validator's `priv_validator_key.json` is stored on a separate, hardened machine running TMKMS
- TMKMS connects to the validator node over a private connection and signs blocks on request
- The validator node itself never has access to the signing key
- Supported backends: YubiHSM2, Ledger, softsign (file-based, for testing)

### Why Use TMKMS

- **Double-sign protection**: TMKMS tracks the last signed block height/round and refuses to sign conflicting blocks
- **Key isolation**: Even if the validator node is compromised, the signing key is safe
- **Audit trail**: All signing operations are logged

### Basic Setup

```bash
# Install TMKMS
cargo install tmkms --features=softsign

# Initialize configuration
tmkms init /path/to/tmkms/config

# Import existing key (softsign backend)
tmkms softsign import ~/.intgd/config/priv_validator_key.json \
  -o /path/to/tmkms/secrets/priv_validator_key.softsign

# Configure tmkms.toml to point to your validator
# Start TMKMS
tmkms start -c /path/to/tmkms/config/tmkms.toml
```

### Production Recommendation

For mainnet validators with significant stake, use a YubiHSM2 device with TMKMS. The softsign backend is suitable for testing and low-stake validators.

## Firewall Best Practices

### Validator Node (Behind Sentries)

Only allow traffic from known sentry nodes:

```bash
# Allow SSH from your IP only
sudo ufw allow from <your_ip> to any port 22

# Allow P2P from sentry nodes only
sudo ufw allow from <sentry_a_ip> to any port 26656
sudo ufw allow from <sentry_b_ip> to any port 26656

# Block everything else
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

### Sentry / RPC Node (Public-Facing)

```bash
# Allow SSH from your IP only
sudo ufw allow from <your_ip> to any port 22

# Allow P2P from anyone
sudo ufw allow 26656/tcp

# Allow RPC (only if running a public RPC node)
sudo ufw allow 26657/tcp

# Allow EVM RPC (only if running a public EVM endpoint)
sudo ufw allow 8545/tcp
sudo ufw allow 8546/tcp

# Allow REST API (only if running a public API)
sudo ufw allow 1317/tcp

# Allow gRPC (only if needed)
sudo ufw allow 9090/tcp

# Prometheus (only from monitoring server)
sudo ufw allow from <monitoring_ip> to any port 26660

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

### Key Principle

A validator should expose **only P2P (26656)** publicly, and only if not using the sentry architecture. RPC, EVM, REST, and gRPC endpoints should never be public on a validator node.

## SSH Hardening

### Key-Only Authentication

```bash
# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Set these values:
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
MaxAuthTries 3
LoginGraceTime 30

# Restart SSH
sudo systemctl restart sshd
```

### Fail2ban

```bash
# Install
sudo apt install fail2ban

# Create local config
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local

# Set under [sshd]:
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600

# Start and enable
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo fail2ban-client status sshd
```

### Non-Root User

Always run the node as a non-root user (e.g., `ubuntu` on AWS). Use `sudo` only when needed.

```bash
# If running as root, create a dedicated user
adduser integra --disabled-password
usermod -aG sudo integra

# Copy SSH keys to new user
mkdir -p /home/integra/.ssh
cp ~/.ssh/authorized_keys /home/integra/.ssh/
chown -R integra:integra /home/integra/.ssh
chmod 700 /home/integra/.ssh
chmod 600 /home/integra/.ssh/authorized_keys
```

### SSH Port Change (Optional)

Changing the SSH port from 22 to a non-standard port reduces automated scanning attempts:

```bash
# In /etc/ssh/sshd_config
Port 2222

# Update firewall
sudo ufw allow 2222/tcp
sudo ufw delete allow 22/tcp
sudo systemctl restart sshd
```

## Key Backup Procedures

### Critical Files to Back Up

| File | Location | Purpose | Sensitivity |
|---|---|---|---|
| `priv_validator_key.json` | `~/.intgd/config/` | Block signing key | HIGHEST - loss means double-sign risk |
| `node_key.json` | `~/.intgd/config/` | P2P identity | Medium - can regenerate but changes node ID |
| Keyring directory | `~/.intgd/keyring-test/` or `keyring-os/` | Wallet keys | HIGH - needed to manage validator |
| `priv_validator_state.json` | `~/.intgd/data/` | Last signed state | HIGH - prevents double signing |

### Backup Procedure

```bash
# Create encrypted backup
BACKUP_DIR=~/.integra-backups/$(date +%Y%m%d)
mkdir -p "$BACKUP_DIR"

# Copy critical files
cp ~/.intgd/config/priv_validator_key.json "$BACKUP_DIR/"
cp ~/.intgd/config/node_key.json "$BACKUP_DIR/"
cp -r ~/.intgd/keyring-test/ "$BACKUP_DIR/keyring-test/"

# Encrypt backup
tar czf - "$BACKUP_DIR" | gpg --symmetric --cipher-algo AES256 -o "$BACKUP_DIR.tar.gz.gpg"

# Transfer to secure offline storage
# NEVER store unencrypted validator keys in cloud storage
```

### Key Safety Rules

1. **Never run the same `priv_validator_key.json` on two nodes simultaneously** -- this causes double signing and permanent slashing
2. **Back up `priv_validator_state.json` before any migration** -- this file tracks the last signed block and prevents double signing
3. **If restoring a node, always use the latest `priv_validator_state.json`** -- using a stale state file can cause double signing
4. **Use the `test` keyring backend only for testnets** -- mainnet should use `os` or `file` backend with a strong passphrase

## Rate Limiting for Public RPC Nodes

If you run a public RPC endpoint (separate from your validator), apply rate limiting:

### Nginx Reverse Proxy with Rate Limiting

```nginx
http {
    # Define rate limit zones
    limit_req_zone $binary_remote_addr zone=rpc:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=evm:10m rate=30r/s;

    server {
        listen 443 ssl;
        server_name rpc.yourdomain.com;

        # Cosmos RPC
        location / {
            limit_req zone=rpc burst=20 nodelay;
            proxy_pass http://127.0.0.1:26657;
        }
    }

    server {
        listen 443 ssl;
        server_name evm.yourdomain.com;

        # EVM JSON-RPC
        location / {
            limit_req zone=evm burst=50 nodelay;
            proxy_pass http://127.0.0.1:8545;
        }
    }
}
```

### iptables Rate Limiting (Alternative)

```bash
# Limit new connections to RPC port
sudo iptables -A INPUT -p tcp --dport 26657 -m connlimit --connlimit-above 20 -j DROP
sudo iptables -A INPUT -p tcp --dport 8545 -m connlimit --connlimit-above 50 -j DROP
```

## DDoS Protection Considerations

### Network Level

- Use the sentry node architecture (primary defense)
- Deploy sentries across multiple cloud providers / regions
- Use cloud provider DDoS protection (AWS Shield, Cloudflare Spectrum)
- Enable SYN cookies: `sysctl -w net.ipv4.tcp_syncookies=1`

### Application Level

- Set `max_num_inbound_peers` to a reasonable value (40-100) in config.toml
- Enable `addr_book_strict = true` to reject peers without proper routing
- Monitor for unusual peer behavior and ban misbehaving peers

### Monitoring for Attacks

```bash
# Monitor active connections per IP
ss -tn | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -20

# Monitor connection rate
watch -n 1 'ss -s'

# Check for SYN flood
netstat -n | grep SYN_RECV | wc -l
```

### Response Plan

1. If a sentry is under attack, spin up a replacement sentry in a different region
2. Blackhole attacking IPs at the firewall level
3. If using cloud, enable emergency DDoS protection services
4. The validator continues signing blocks as long as at least one sentry remains connected
