# Deploying Lambda

Lambda spans three chains. Deploy in this order; each leg needs the previous one's address.

```
① Unichain      LambdaHook (+ Funding, InsuranceVault)   → emits HedgeRequested
② HyperEVM      LambdaHedger                              → fires the perp via CoreWriter
③ Reactive      LambdaReactive                            → wires ① → ② (needs both addresses)
```

All chain-specific addresses are read from the environment; nothing is hard-coded. Fill these
in for your target testnets (Unichain Sepolia, HyperEVM testnet, Reactive Lasna), then run the
scripts. The CoreWriter precompile (`0x3333…3333`) and the Reactive service contract
(`0x…fffFfF`) are fixed and already baked in.

## 0. Common

```bash
export PRIVATE_KEY=0x...          # broadcaster; must be the intended OWNER for the wiring calls
# export OWNER=0x...              # optional; defaults to the broadcaster
```

## ① Unichain: hook, funding, insurance

```bash
export POOL_MANAGER=0x...         # Uniswap v4 PoolManager on the target chain
export TOKEN0=0x...               # pool tokens (any order; the script sorts them)
export TOKEN1=0x...               # the numéraire leg (e.g. USDC), also the funding token
# Optional pool/risk params (sensible defaults shown):
# export TICK_SPACING=60  TICK_LOWER=-600  TICK_UPPER=600
# export TAU=1000000000000000      # 1e15, re-hedge band in token0 units
# export HEDGE_RATIO_WAD=0         # 0 ⇒ contract default 0.65e18
# export SQRT_PRICE_X96=...        # initial price; default = 1:1
# Optional insurance reserve (omit RESERVE_ASSET to skip the vault):
# export RESERVE_ASSET=0x...  COVERER=0x...

forge script contracts/script/DeployUnichain.s.sol --rpc-url "$UNICHAIN_RPC" --broadcast
# → prints LambdaHook, Funding, InsuranceVault, poolId, and the HedgeRequested topic0
```

The hook is deployed via CREATE2 to a mined address whose low 14 bits encode its v4
permissions (`beforeAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`); the
script mines the salt with `HookMiner` and asserts the deployed address matches.

## ② HyperEVM: the hedger

```bash
export CALLBACK_SENDER=0x...      # the Reactive callback proxy on HyperEVM (authorizes applyHedge)
forge script contracts/script/DeployHyperEVM.s.sol --rpc-url "$HYPEREVM_RPC" --broadcast
# → prints LambdaHedger
```

Then calibrate the perp market for your pool (owner tx):
`hedger.configureMarket(poolId, assetIndex, szScaleWad, pxScaleWad, slippageBps, tif)`.

## ③ Reactive: the brain

```bash
export ORIGIN_CHAIN_ID=...        # Unichain chain id
export DESTINATION_CHAIN_ID=...   # HyperEVM chain id
export HOOK=0x...                 # from ①
export HEDGER=0x...               # from ②
# export CRON_TOPIC=0x...         # optional cron topic for funding checkpoints; 0 disables
# export CALLBACK_GAS_LIMIT=1000000
forge script contracts/script/DeployReactive.s.sol --rpc-url "$REACTIVE_RPC" --broadcast
# → subscribes to the hook's HedgeRequested (topic0 printed by ①) and routes callbacks to ②
```

## 4. Post-deploy wiring (owner)

- Fund `LambdaReactive` with REACT for callback gas (Reactive Network requirement).
- Authorize the funding bridge/operator: `funding.setFunder(addr, true)`.
- If using insurance: set `vault.setCoverer(hedgerOrOperator)` and, for yield, deploy
  `AaveV3Venue` and call `vault.setVenue(venue)`.

## Verifying the subscription topic

The `HedgeRequested` topic0 (`keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)")`)
is printed by the Unichain script and is what `LambdaReactive` subscribes to. Confirm they match.
