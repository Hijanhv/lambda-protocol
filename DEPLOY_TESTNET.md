# Lambda — Testnet Deploy Runbook (UHI9 build week)

Copy-paste, in order. This is the **testnet** path (free) for build week; the mainnet
addresses for Demo Day are noted at the bottom. Three legs, deployed in order — each later
leg needs an address the earlier one prints.

> ⚠️ **Testnet topology constraint (confirmed 2026-05-25 via dev.reactive.network/origins-and-destinations):**
> Reactive **Lasna** can deliver callbacks to Ethereum Sepolia, Base Sepolia, **Unichain Sepolia**,
> and Lasna itself — but **NOT to HyperEVM testnet (998)**. HyperEVM is a Reactive destination only
> on **mainnet (999)**. So the *fully auto-wired* loop (Unichain → Reactive → real CoreWriter perp)
> is **mainnet-only**. On testnet you prove the two halves separately — see "Testnet topology" below.
>
> Confirmed: HyperEVM testnet RPC `https://rpc.hyperliquid-testnet.xyz/evm`; Unichain Sepolia (1301)
> is a Lasna origin **and** destination, callback proxy `0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4`.

---

## Testnet topology — how to demo the cross-chain hedge without mainnet

Because Lasna can't reach HyperEVM 998, prove the differentiator in **two halves** on testnet:

1. **Reactive automation (the "no bot, cross-chain" claim):** hook on Unichain Sepolia emits
   `HedgeRequested` → Reactive Lasna catches it → callback delivered to a supported destination
   (use **Unichain Sepolia** as both origin and destination, `DESTINATION_CHAIN_ID=1301`). Proves the
   automatic cross-chain trigger end-to-end.
2. **Real Hyperliquid hedge (the "real, not simulated" claim):** deploy `LambdaHedger` on **HyperEVM
   testnet (998)** and trigger `applyHedge` directly (owner/relayer) → it calls the real CoreWriter
   precompile `0x3333…3333` → a real testnet perp opens. Proves the real venue.

On **mainnet** (if we win) the two halves wire directly: Reactive Mainnet → HyperEVM 999 is a supported
destination, so `DESTINATION_CHAIN_ID=999` makes the whole loop automatic. Same contracts, no code change.

---

## 0 · Common — deployer key + faucets

> 💰 **Fund THIS address on every chain** (UHI9 Deploy account, also the contract OWNER):
> **`0x35d8E75295366e6A12B988084096d89233dF4e9C`**
> Same address on Sepolia, Unichain Sepolia, Reactive Lasna, and HyperEVM testnet.

**Signing — pick one.** The encrypted keystore keeps the raw key out of your shell history/env:

```bash
export DEPLOYER=0x35d8E75295366e6A12B988084096d89233dF4e9C

# Option A (recommended): keystore — import once, then use --account on every script
cast wallet import uhi9 --interactive          # paste key once, set a password
#   → forge script ... --account uhi9 --sender "$DEPLOYER" --broadcast

# Option B: raw key in env (simpler, less safe)
export PRIVATE_KEY=0x...                        # the UHI9 Deploy key
#   → forge script ... --private-key "$PRIVATE_KEY" --broadcast
```

The commands below show `--private-key "$PRIVATE_KEY"`; if you used Option A, swap that for
`--account uhi9 --sender "$DEPLOYER"`.

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

On testnet this leg runs **standalone** (Reactive Lasna can't reach 998, so it's triggered
directly — see "Testnet topology" above). `CALLBACK_SENDER` is the address allowed to call
`applyHedge` — for the testnet demo, your owner/relayer EOA (on mainnet it's the `0x9299…FC4`
Reactive proxy).

```bash
export HYPEREVM_RPC=https://rpc.hyperliquid-testnet.xyz/evm   # confirmed testnet EVM RPC (chain 998)
export CALLBACK_SENDER=0x...                                  # testnet: your owner/relayer EOA that triggers applyHedge

forge script contracts/script/DeployHyperEVM.s.sol \
  --rpc-url "$HYPEREVM_RPC" --private-key "$PRIVATE_KEY" --broadcast
# → prints: LambdaHedger
```

Then calibrate the perp market (owner tx) and trigger one hedge directly to prove the real perp:
```
hedger.configureMarket(poolId, assetIndex, szScaleWad, pxScaleWad, slippageBps, tif)
hedger.applyHedge(...)   # owner/relayer call → real CoreWriter perp on Hyperliquid testnet
```

---

## 4 · Leg ③ — Reactive Lasna (the brain) — wires ① → ②

On testnet the destination is **Unichain Sepolia (1301)**, not HyperEVM — Lasna can't reach 998
(see "Testnet topology"). This proves the automatic cross-chain trigger; the destination-side
receiver on Unichain Sepolia is `LambdaHedgeReceiver` (records the hedge + emits an event with the
same auth/nonce rules as the real hedger, minus the CoreWriter order). The real CoreWriter call is
shown separately on 998 in leg ②. On mainnet, set `DESTINATION_CHAIN_ID=999` and use the real
`LambdaHedger` as `HEDGER` — no code change.

First deploy the receiver on Unichain Sepolia (its `CALLBACK_SENDER` is the Lasna→Unichain-Sepolia proxy):
```bash
export CALLBACK_SENDER=0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4   # Unichain Sepolia callback proxy
forge script contracts/script/DeployReceiver.s.sol \
  --rpc-url "$UNICHAIN_RPC" --private-key "$PRIVATE_KEY" --broadcast
# → prints: LambdaHedgeReceiver   (use as HEDGER below)
```

Then deploy the Reactive contract on Lasna.

> ⚠️ **`forge script` can NOT deploy `LambdaReactive`.** Its constructor calls Reactive's
> `subscribe` precompile (at `0x64`), which reverts in forge's local execution/simulation
> (the precompile only exists on real Reactive nodes). `--skip-simulation` doesn't help —
> forge still runs the constructor locally to collect the tx. **Deploy with `cast send --create`
> instead**, so the constructor runs only on-chain:

```bash
export REACTIVE_RPC=https://lasna-rpc.rnk.dev          # Reactive Lasna (verified, chainId 5318007)
HOOK=0x...        # from leg ①
HEDGER=0x...      # the LambdaHedgeReceiver from above (testnet) / real LambdaHedger (mainnet)
ORIGIN=1301       # Unichain Sepolia (Lasna origin ✅)
DEST=1301         # testnet: Unichain Sepolia (Lasna dest ✅). Mainnet: 999 (HyperEVM)

BYTECODE=$(jq -r '.bytecode.object' out/LambdaReactive.sol/LambdaReactive.json)
ARGS=$(cast abi-encode "f(uint256,address,uint256,address,uint256,uint64)" $ORIGIN $HOOK $DEST $HEDGER 0 1000000)
cast send --rpc-url "$REACTIVE_RPC" --account uhi9 --sender "$DEPLOYER" --create "${BYTECODE}${ARGS#0x}"
# → constructor (uint256 originChainId, address hook, uint256 destChainId, address hedger, uint256 cronTopic, uint64 callbackGasLimit)
# → the receipt's `contractAddress` is your LambdaReactive; it subscribes to HedgeRequested on the origin
```

Then **fund it for callbacks** (Reactive pays callback gas from the contract's REACT balance):
```bash
cast send <LambdaReactive> --value 2ether --rpc-url "$REACTIVE_RPC" --account uhi9 --sender "$DEPLOYER"
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

## 7 · Seed the demo (one command)

After ① (and ③, so the callback routes), seed the pool and fire a hedge in one shot. This
deposits liquidity (fires the first `HedgeRequested`) then swaps to move the price (fires a
second, drift-triggered one). It also makes the dashboard's deposit quoter work (it needs a
non-empty pool to quote against). Uses the tokens minted in step 1.

```bash
export HOOK=0x...          # from leg ①
# POOL_MANAGER, TOKEN0, TOKEN1 already exported from step 2
# export SEED_LIQ=1000000000000000000000   # optional, default 1e21
# export SWAP_AMOUNT=1000000000000000000   # optional, default 1e18 (raise if no 2nd hedge fires)

forge script contracts/script/SeedDemo.s.sol \
  --rpc-url "$UNICHAIN_RPC" --private-key "$PRIVATE_KEY" --broadcast
# → prints seeded shares, pool liquidity, hedge nonce, poolId
```

Watch the hedge land: the `HedgeRequested` tx on uniscan → the callback on reactscan → on testnet
it hits the `LambdaHedgeReceiver` (Unichain Sepolia). The real CoreWriter perp is shown separately
on HyperEVM 998 (leg ②).

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
