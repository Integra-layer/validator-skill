---
name: generate-connect-page
description: Scaffold a validator monitoring and wallet-connect landing page from templates
---

# Generate Connect Page

Scaffold a Next.js landing page for your Integralayer validator — includes one-click wallet setup (MetaMask, Keplr, OKX), live chain status, RPC health dashboard, and network configuration details.

Based on the [integra-connect](https://integra-connect.vercel.app) reference implementation.

## Prerequisites

- Node.js 18+ and npm
- A deployed validator node with DNS (see `setup-caddy` skill for HTTPS)

## Input Parameters

Collect these from the user before starting:

| Parameter | Example | Description |
|-----------|---------|-------------|
| `PROJECT_NAME` | `integra-connect` | npm package name |
| `PAGE_TITLE` | `Integra Connect` | Browser tab title |
| `CHAIN_ID` | `integra-1` | Cosmos chain ID |
| `CHAIN_NAME` | `Integra Mainnet` | Display name |
| `EVM_CHAIN_ID` | `26217` | Numeric EVM chain ID |
| `EVM_CHAIN_ID_HEX` | `0x6669` | Hex EVM chain ID |
| `BECH32_PREFIX` | `integra` | Bech32 address prefix |
| `RPC_URL` | `https://node.example.com/rpc` | EVM JSON-RPC endpoint |
| `WS_URL` | `wss://node.example.com/ws` | EVM WebSocket endpoint |
| `COMETBFT_URL` | `https://node.example.com/cometbft` | CometBFT RPC endpoint |
| `DNS` | `node.example.com` | Validator DNS hostname |
| `DENOM` | `IRL` | Display token symbol |
| `MIN_DENOM` | `airl` | Base denomination |
| `DECIMALS` | `18` | Token decimals |
| `VALIDATOR_ADDRESS` | `integra1abc...` | Bech32 validator address |
| `OPERATOR_NAME` | `adamboudj` | Operator display name |
| `NODE_IP` | `3.92.110.107` | Node IP address |

## Workflow

### Step 1: Create Project Directory

```bash
mkdir <PROJECT_NAME>
cd <PROJECT_NAME>
```

### Step 2: Read scaffold.json

Read the manifest at `templates/connect-page/scaffold.json` to get:
- The list of all template files and their output paths
- Variable definitions and validation rules

### Step 3: Process Each Template

For each entry in `scaffold.json.files`:

1. Read the template file from `templates/connect-page/<template>`
2. Replace all `{{VARIABLE}}` placeholders with the user's values
3. Create the output directory if needed (`mkdir -p`)
4. Write the processed content to `<output>` path

**Variable replacement** is simple string substitution:
```
{{CHAIN_ID}} → integra-1
{{CHAIN_NAME}} → Integra Mainnet
{{EVM_CHAIN_ID}} → 26217
... etc
```

### Step 4: Install Dependencies

```bash
npm install
```

Required packages (already in package.json template):
- `next` (^15.1.0)
- `react` + `react-dom` (^19.0.0)
- `lucide-react` (icons)
- `sonner` (toast notifications)
- `tailwindcss` + `@tailwindcss/postcss` (styling)
- `typescript` + `@types/react` + `@types/node`

### Step 5: Verify Build

```bash
npm run build
```

The build must succeed with zero errors. If it fails:
- Check that all `{{VARIABLE}}` placeholders were replaced
- Verify the chain-config.ts has valid JavaScript (numeric values not quoted)
- Ensure all import paths resolve correctly

### Step 6: Test Locally (Optional)

```bash
npm run dev
```

Visit `http://localhost:3000` to verify:
- [ ] Hero section shows correct chain name and token
- [ ] Wallet buttons render (MetaMask, Keplr, OKX)
- [ ] Chain status section attempts to connect to CometBFT URL
- [ ] Health dashboard runs RPC checks through the proxy API route
- [ ] Network info table shows correct URLs and chain IDs
- [ ] Footer shows operator name and validator address

### Step 7: Deploy

**Vercel (recommended):**
```bash
npx vercel --prod
```

**Netlify:**
```bash
npx netlify deploy --prod --dir=.next
```

**Self-hosted:**
```bash
npm run build
npm start  # runs on port 3000
```

Use Caddy or nginx to reverse proxy port 3000 if hosting alongside the validator.

## Architecture Notes

The generated page uses:
- **Next.js App Router** with server and client components
- **API routes** (`/api/rpc`, `/api/status`) as CORS proxies for the validator's RPC endpoints — this avoids mixed-content blocks when the page is served over HTTPS
- **WebSocket hook** with polling fallback for live block updates
- **Tailwind CSS v4** with custom theme tokens (brand colors, status colors)
- All chain configuration centralized in `src/lib/chain-config.ts`

## Cross-References

- `setup-caddy` — Set up HTTPS reverse proxy (required for RPC_URL/WS_URL/COMETBFT_URL)
- `references/network-config.md` — Chain parameters for variable values
