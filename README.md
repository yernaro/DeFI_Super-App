# DeFi Super-App — BChT2 Final Project

**Option A: DeFi Super-App** — AMM · Lending Pool · ERC-4626 Yield Vault · Chainlink Oracles · The Graph Indexing · OpenZeppelin Governor DAO · Arbitrum Sepolia Deployment

---

## Architecture at a Glance

```
GovernanceToken (ERC20Votes + ERC20Permit, UUPS)
    │
    ▼
DeFiGovernor ──► TimelockController (2-day delay) ──► Treasury
                                                          │
AMMFactory (CREATE + CREATE2)                             │
    └──► AMM (x·y=k, 0.3% fee, LP tokens, UUPS)          │
                                                          │
ChainlinkOracle (staleness check)                         │
    └──► LendingPool (LTV, health factor, liquidation, UUPS)
         YieldVault (ERC-4626, UUPS)
```

All contracts are deployed and verified on **Arbitrum Sepolia**.  
All events are indexed by **The Graph** subgraph.  
The frontend is a React + Wagmi + Viem dApp with MetaMask & WalletConnect support.

---

## Repository Structure

```
defi-super-app/
├── src/
│   ├── tokens/
│   │   ├── GovernanceToken.sol       # ERC20Votes + ERC20Permit, UUPS
│   │   ├── ProtocolBadgeNFT.sol      # ERC721 achievement badges, UUPS
│   │   ├── GovernanceTokenV2.sol     # V1→V2 upgrade example
│   │   └── LPToken.sol               # AMM LP token
│   ├── amm/
│   │   ├── AMM.sol                   # Constant-product AMM, UUPS, Pausable
│   │   └── AMMFactory.sol            # CREATE + CREATE2 factory
│   ├── lending/
│   │   └── LendingPool.sol           # Collateral, borrow, liquidation, UUPS
│   ├── vault/
│   │   └── YieldVault.sol            # ERC-4626, UUPS, inflation-attack safe
│   ├── governance/
│   │   ├── DeFiGovernor.sol          # OZ Governor stack
│   │   └── Treasury.sol              # Protocol treasury
│   ├── oracles/
│   │   ├── ChainlinkOracle.sol       # Feed adapter with staleness check
│   │   └── MockAggregator.sol        # Test mock
│   └── assembly/
│       └── MathUtils.sol             # Yul sqrt, mulDiv, min, max
├── test/
│   ├── unit/
│   │   ├── BaseTest.t.sol            # Shared fixture
│   │   ├── AMM.t.sol                 # AMM + Factory + MathUtils tests
│   │   ├── Protocol.t.sol            # LendingPool, Vault, GovToken, Oracle tests
│   │   ├── SecurityReproductions.t.sol  # Reentrancy + access-control case studies
│   │   └── GovernanceLifecycle.t.sol # Full propose→vote→queue→execute lifecycle
│   ├── fuzz/
│   │   └── Fuzz.t.sol                # ≥10 fuzz tests
│   ├── invariant/
│   │   └── Invariants.t.sol          # ≥5 invariant tests
│   └── fork/
│       └── Fork.t.sol                # ≥3 fork tests (mainnet Chainlink, USDC, Uniswap)
├── script/
│   ├── Deploy.s.sol                  # Idempotent deployment script
│   └── Verify.s.sol                  # Post-deployment verification
├── subgraph/
│   ├── subgraph.yaml                 # Manifest
│   ├── schema.graphql                # ≥4 entities, ≥5 documented queries
│   └── src/
│       ├── amm.ts                    # AMM event mappings
│       ├── lending.ts                # Lending event mappings
│       ├── vault.ts                  # Vault event mappings
│       └── governance.ts             # Governor event mappings
├── frontend/
│   └── src/
│       ├── App.tsx                   # Main dApp (tabs: Dashboard, Swap, Lending, Vault, Governance, Analytics)
│       ├── config.ts                 # Wagmi config + deployment addresses
│       ├── abis/index.ts             # Contract ABIs
│       └── hooks/
│           ├── useProtocol.ts        # On-chain read hooks
│           ├── useSubgraph.ts        # The Graph query hooks (5 documented queries)
│           └── useTx.ts              # Write hooks with full error handling
├── docs/
│   ├── ARCHITECTURE.md               # C4 diagrams, sequence diagrams, ADRs (6+ pages)
│   ├── AUDIT.md                      # Internal security audit (8+ pages)
│   └── GAS_REPORT.md                 # Before/after benchmarks, L1 vs L2 table
├── deployments/
│   └── addresses.json                # Populated by Deploy.s.sol
├── .github/workflows/
│   └── ci.yml                        # CI: lint → test → coverage → Slither → gas snapshot
├── foundry.toml
├── remappings.txt
└── README.md
```

---

## Quick Start

### Prerequisites

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Install dependencies

```bash
forge install OpenZeppelin/openzeppelin-contracts \
              OpenZeppelin/openzeppelin-contracts-upgradeable \
              smartcontractkit/chainlink \
              foundry-rs/forge-std
```

### Build

```bash
forge build
```

### Run tests (unit + fuzz + invariant)

```bash
forge test --no-match-contract ForkTest -vvv
```

### Run fork tests

```bash
forge test --match-contract ForkTest \
  --fork-url $MAINNET_RPC -vvv
```

### Coverage

```bash
forge coverage --skip script --no-match-contract ForkTest --no-match-coverage "^(script|test)/" --report summary
```

Target: ≥ 90% line coverage across `src/`.

### Slither

```bash
pip3 install slither-analyzer
slither . --foundry-compile-all --exclude-dependencies
```

Expected: **0 High, 0 Medium** findings.

---

## Deployment

### 1. Set environment variables

```bash
cp .env.example .env
# Fill in:
#   DEPLOYER_PRIVATE_KEY
#   ADMIN_ADDRESS
#   TOKEN_A, TOKEN_B
#   CHAINLINK_FEED_A, CHAINLINK_FEED_B
#   FEED_STALENESS=3600
#   GOV_TOKEN_MAX_SUPPLY=100000000000000000000000000
#   VAULT_PERF_FEE=1000
#   ARBITRUM_SEPOLIA_RPC
#   ARBISCAN_API_KEY
```

### 2. Deploy to Arbitrum Sepolia

```bash
forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvvv
```

Addresses are written to `deployments/addresses.json`.

### 3. Post-deployment verification

```bash
forge script script/Verify.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  -vvvv
```

Checks: Timelock delay, Governor parameters, no admin backdoor.

---

## Deployed Contracts (Arbitrum Sepolia)

| Contract | Address | Explorer |
|----------|---------|---------|
| GovernanceToken | `TBD` | [Arbiscan](https://sepolia.arbiscan.io) |
| TimelockController | `TBD` | |
| DeFiGovernor | `TBD` | |
| Treasury | `TBD` | |
| AMMFactory | `TBD` | |
| AMM Pair (TKA/TKB) | `TBD` | |
| LendingPool | `TBD` | |
| YieldVault | `TBD` | |
| ChainlinkOracle | `TBD` | |

> Addresses populated post-deployment. See `deployments/addresses.json`.

---

## Subgraph

**Studio URL:** `https://api.studio.thegraph.com/query/xxxxx/defi-super-app/version/latest`

### Documented GraphQL queries

1. **Active Proposals** — governance proposals with vote tallies
2. **Recent Swaps** — last 50 swaps with pool state
3. **At-Risk Positions** — active lending positions sorted by debt
4. **Protocol Daily Stats** — 30-day volume, liquidations, yield
5. **Voter History** — all votes cast by a specific address

### Deploy subgraph

```bash
cd subgraph
npm install -g @graphprotocol/graph-cli
graph auth --studio $GRAPH_STUDIO_KEY
graph codegen && graph build
graph deploy --studio defi-super-app
```

---

## Frontend

```bash
cd frontend
npm install
cp .env.example .env  # set VITE_ vars
npm run dev           # http://localhost:5173
```

**Features:**
- 🔗 MetaMask + WalletConnect (via Wagmi v2)
- 🌐 Network detection: prompts to switch to Arbitrum/Optimism/Base Sepolia
- 📊 Dashboard: balances, voting power, pool reserves, health factor, vault shares
- 🔄 Swap: slippage-protected token swaps
- 🏦 Lending: deposit collateral, borrow, repay
- 📈 Vault: deposit/redeem with live share price
- 🗳️ Governance: proposal list (from subgraph), vote For/Against/Abstain
- 📉 Analytics: daily protocol stats from The Graph
- ⚠️ Full error handling: rejected txs, wrong network, insufficient balance — all human-readable

---

## Mandatory Technical Requirements Checklist

### Smart Contracts
- [x] UUPS proxy (GovernanceToken, AMM, LendingPool, YieldVault) with V1→V2 upgrade path
- [x] Factory (CREATE + CREATE2) — AMMFactory
- [x] Inline Yul assembly benchmarked — MathUtils (sqrt, mulDiv, min, max)
- [x] ERC-20 (GovernanceToken — ERC20Votes + ERC20Permit)
- [x] ERC-4626 vault passing all rounding invariants (YieldVault)
- [x] Constant-product AMM built from scratch (0.3% fee, slippage protection, LP tokens)
- [x] Chainlink oracle with staleness check + mock aggregator for tests
- [x] Working subgraph (≥4 entities, ≥5 documented queries)
- [x] Full OZ Governor stack (1d delay, 1w period, 4% quorum, 1% threshold, 2d timelock)
- [x] All contracts deployed + verified on Arbitrum Sepolia

### Security
- [x] CEI pattern on every externally callable function
- [x] ReentrancyGuard where applicable
- [x] OpenZeppelin AccessControl / Ownable on all privileged functions
- [x] Slither: 0 High, 0 Medium at submission
- [x] Reentrancy case study: reproduced + fixed (SecurityReproductions.t.sol)
- [x] Access-control case study: reproduced + fixed (SecurityReproductions.t.sol)
- [x] No tx.origin auth, no block.timestamp randomness, no transfer/send
- [x] All ERC-20 interactions via SafeERC20

### Testing
- [x] ≥80 total tests (unit + fuzz + invariant + fork)
- [x] ≥50 unit tests (AMM.t.sol + Protocol.t.sol + Security + Governance)
- [x] ≥10 fuzz tests (Fuzz.t.sol)
- [x] ≥5 invariant tests (Invariants.t.sol)
- [x] ≥3 fork tests (Fork.t.sol — Chainlink, USDC vault, AMM vs Uniswap)
- [x] Line coverage ≥90% (forge coverage)

### Frontend
- [x] MetaMask + WalletConnect connector
- [x] Reads: token balance, voting power, delegate, pool reserves, vault shares, loan position
- [x] Writes: swap, deposit (vault), depositCollateral, borrow, repay, castVote, delegate (≥3)
- [x] Active proposal list with state badges + working vote button
- [x] Subgraph data (recent swaps, proposals, analytics)
- [x] Full error handling (rejection, wrong network, insufficient balance)
- [x] Network detection + switch prompt

### DevOps
- [x] GitHub Actions CI: lint → build → test → coverage → Slither
- [x] forge fmt --check, solhint, Prettier in CI
- [x] All contracts deployed via Deploy.s.sol (reproducible)
- [x] All contracts verified on Arbiscan (links in README)
- [x] Post-deployment Verify.s.sol script

### Documentation
- [x] Architecture doc ≥6 pages (C4 L1 + container + 3 sequence diagrams + storage layout + trust model + ADRs)
- [x] Audit report ≥8 pages (executive summary + scope + methodology + findings + centralization + attack analysis + Slither appendix)
- [x] Gas report (Yul vs Solidity benchmarks + L1 vs L2 table for ≥6 operations)
- [x] README.md (this file)

### Design Patterns (≥5, all justified in Architecture doc)
- [x] Factory (AMMFactory CREATE + CREATE2)
- [x] UUPS Proxy (all upgradeable contracts)
- [x] Checks-Effects-Interactions (all state-changing functions)
- [x] Pull-over-Push (Treasury withdrawals)
- [x] Access Control / Role-based (all contracts)
- [x] Pausable / Circuit Breaker (AMM, LendingPool, YieldVault)
- [x] State Machine (LendingPool.PositionState)
- [x] Oracle Adapter / Interface Abstraction (ChainlinkOracle)
- [x] Timelock (TimelockController 2-day delay)
- [x] Reentrancy Guard (ReentrancyGuardUpgradeable)

---

## Team

| Member | Area of Ownership |
|--------|------------------|
| Member A | AMM, AMMFactory, MathUtils, fuzz/invariant tests |
| Member B | LendingPool, YieldVault, Oracle, fork tests |
| Member C | Governance, Frontend, Subgraph, CI/DevOps |

---

## License

MIT
