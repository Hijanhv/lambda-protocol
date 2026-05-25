# Lambda — Testnet Deploy Runbook (UHI9 build week)

Copy-paste, in order. This is the **testnet** path (free) for build week; the mainnet
addresses for Demo Day are noted at the bottom. Three legs, deployed in order — each later
leg needs an address the earlier one prints.

> ⚠️ **Three values still need confirmation before broadcasting** (marked `‹CONFIRM›` below):
> the HyperEVM **testnet** callback-proxy address and RPC, and whether **Reactive Lasna**
> supports Unichain Sepolia (1301) as an origin and HyperEVM testnet (998) as a destination.
> Everything else is verified live (see `lambda` ideation repo → `verified_addresses_and_topics.md`).

---

## 0 · Common — deployer key + faucets

Use a **fresh** MetaMask account dedicated to UHI9. The same key gives the same address on
every chain. Never paste the seed/key anywhere or commit it.

```bash
export PRIVATE_KEY=0x...        # fresh UHI9 deployer (also the OWNER for wiring calls)
```

Faucets (all free):
| Need | Where |
|---|---|
| Sepolia ETH | Alchemy / QuickNode / Google Cloud faucets |
| **Lasna lREACT** | send ≥1 Sepolia ETH to `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` → 100 lREACT |
| Unichain Sepolia ETH | https://uniswap.org/faucet (or bridge Sepolia ETH) |
| HyperEVM testnet gas + test USDC | Hyperliquid testnet faucet (`app.hyperliquid-testnet.xyz`) |

---

## 1 · Test tokens (Unichain Sepolia) — gives the hook a pool to manage

```bash
export UNICHAIN_RPC=https://sepolia.unichain.org

forge script contracts/script/DeployTestTokens.s.sol \
  --rpc-url "$UNICHAIN_RPC" --private-key "$PRIVATE_KEY" --broadcast
# → prints: tWETH (18d) 0x…   tUSDC (6d) 0x…
```

Save those two addresses.

---

## 2 · Leg ① — Unichain Sepolia (the hook)

```bash
export POOL_MANAGER=0x00b036b58a818b1bc34d502d3fe730db729e62ac   # Uniswap v4 PoolManager, Unichain Sepolia (verified, docs)
export TOKEN0=0x...   # tWETH from step 1
export TOKEN1=0x...   # tUSDC from step 1

# Optional (sensible defaults shown):
# export TICK_SPACING=60  TICK_LOWER=-600  TICK_UPPER=600
# export TAU=1000000000000000          # 1e15, re-hedge band in token0 units
# export HEDGE_RATIO_WAD=0             # 0 ⇒ contract default 0.65e18
# export SQRT_PRICE_X96=...            # default 1:1; set for a realistic ETH/USDC price

forge script contracts/script/DeployUnichain.s.sol \
  --rpc-url "$UNICHAIN_RPC" --private-key "$PRIVATE_KEY" --broadcast
# → prints: LambdaHook, Funding, InsuranceVault, salt, poolId, HedgeRequested topic0
```

Save **LambdaHook**, **Funding**, **poolId**, and the **HedgeRequested topic0**.

---

## 3 · Leg ② — HyperEVM testnet (the hedger)

```bash
export HYPEREVM_RPC=https://rpc.hyperliquid-testnet.xyz/evm        # ‹CONFIRM› testnet EVM RPC
export CALLBACK_SENDER=0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4 # ‹CONFIRM› — this is the VERIFIED mainnet (999) proxy; confirm it's the same on testnet 998

forge script contracts/script/DeployHyperEVM.s.sol \
  --rpc-url "$HYPEREVM_RPC" --private-key "$PRIVATE_KEY" --broadcast
# → prints: LambdaHedger
```

Then calibrate the perp market (owner tx):
```
hedger.configureMarket(poolId, assetIndex, szScaleWad, pxScaleWad, slippageBps, tif)
```

---

## 4 · Leg ③ — Reactive Lasna (the brain) — wires ① → ②

```bash
export REACTIVE_RPC=https://lasna-rpc.rnk.dev          # Reactive Lasna (verified, chainId 5318007)
export ORIGIN_CHAIN_ID=1301                            # Unichain Sepolia    ‹CONFIRM Lasna supports it as origin›
export DESTINATION_CHAIN_ID=998                        # HyperEVM testnet    ‹CONFIRM Lasna supports it as destination›
export HOOK=0x...                                      # from leg ①
export HEDGER=0x...                                    # from leg ②
# export CRON_TOPIC=0x...        # optional funding-checkpoint cron; 0 disables
# export CALLBACK_GAS_LIMIT=1000000

forge script contracts/script/DeployReactive.s.sol \
  --rpc-url "$REACTIVE_RPC" --private-key "$PRIVATE_KEY" --broadcast
# → subscribes to HedgeRequested (topic0 from ①) and routes callbacks to ②
```

---

## 5 · Post-deploy wiring (owner txs)

- Fund `LambdaReactive` with **lREACT** for callback gas (Reactive requirement).
- `funding.setFunder(operator, true)` — authorize the funding bridge/operator.
- (Insurance, optional) `vault.setCoverer(hedgerOrOperator)`; for yield, deploy `AaveV3Venue`
  and `vault.setVenue(venue)`. **Note:** Aave V3 is **not** on Unichain — leave the reserve
  idle on Unichain Sepolia, or run the venue on Base. (See ideation `verified_addresses…md §7`.)

---

## 6 · Point the frontend at it → `frontend/.env.local`

After leg ①, drop in the printed addresses (token symbols/decimals match step 1):

```bash
NEXT_PUBLIC_CHAIN_ID=1301
NEXT_PUBLIC_CHAIN_NAME=Unichain Sepolia
NEXT_PUBLIC_RPC_URL=https://sepolia.unichain.org
NEXT_PUBLIC_HOOK_ADDRESS=0x...        # LambdaHook
NEXT_PUBLIC_FUNDING_ADDRESS=0x...     # Funding
NEXT_PUBLIC_POOL_ID=0x...             # poolId
NEXT_PUBLIC_TOKEN0=0x...              # tWETH
NEXT_PUBLIC_TOKEN1=0x...              # tUSDC
NEXT_PUBLIC_TOKEN0_SYMBOL=tWETH
NEXT_PUBLIC_TOKEN1_SYMBOL=tUSDC
NEXT_PUBLIC_TOKEN0_DECIMALS=18
NEXT_PUBLIC_TOKEN1_DECIMALS=6
NEXT_PUBLIC_TICK_SPACING=60
```

Restart `npm run dev` → the dashboard leaves "Demo mode" and reads live data.

---

## Verified fixed addresses (baked into `LambdaConfig.sol`, no env needed)

| What | Address | Chain |
|---|---|---|
| CoreWriter precompile | `0x3333333333333333333333333333333333333333` | HyperEVM (998 / 999) |
| Reactive system contract | `0x0000000000000000000000000000000000fffFfF` | Reactive (Lasna / Mainnet) |
| CREATE2 deployer (hook miner target) | `0x4e59b44847b379578588920cA78FbF26c0B4956C` | all |

## Mainnet values for Demo Day (Jun 7–9 deploy)

| Leg | Chain | RPC | Key address |
|---|---|---|---|
| ① | Unichain Mainnet (130) | https://mainnet.unichain.org | PoolManager `0x1f98400000000000000000000000000000000004` |
| ② | HyperEVM Mainnet (999) | https://rpc.hyperliquid.xyz/evm | callback proxy `0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4` (verified) |
| ③ | Reactive Mainnet (1597) | https://mainnet-rpc.rnk.dev | system contract `0x…fffFfF` |

Mainnet funding ≈ $40–55 (Unichain ETH + ~5 HYPE + ~10 USDC margin + ~5 REACT). The hedger
needs **≥ $10 USDC margin** to open a real perp for the demo — judges will check hyperevmscan.
