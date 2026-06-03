# Technical verification — Lambda Protocol

This document records a direct cross-check of Lambda's three partner integrations against
each chain's **authoritative source** — the vendored libraries that actually compile into the
contracts (`lib/v4-core`, `lib/reactive-lib`) and the official Hyperliquid CoreWriter docs.
The intent is that a judge can confirm the integrations are real and correct without taking
anything on faith.

**Status at time of writing:** `forge build` clean (no warnings), **134 tests across 17
suites** (incl. invariant fuzzing) — 127 unit/invariant passing offline, plus 7 fork tests
that exercise all three legs against their real chains' state: legs ① + ③ on a Unichain
Sepolia fork and leg ② (the real `LambdaHedger` firing a CoreWriter short) on a HyperEVM
mainnet fork. The fork tests self-skip when no RPC is set. `LambdaHook` 14,393 bytes
(< 24,576 deploy limit).

---

## ① Uniswap v4 — the hook

### Hook permission bits are mined into the deployed address

v4 derives a hook's permissions from the low 14 bits of its address; `LambdaHook`'s
constructor calls `Hooks.validateHookPermissions(this, getHookPermissions())`, which **reverts
on any mismatch**. So the live address is itself the proof the flags are right.

`getHookPermissions()` enables four callbacks → expected flag bits:

| Permission | Flag (`lib/v4-core/src/libraries/Hooks.sol`) | Value |
|---|---|---|
| `beforeAddLiquidity` | `1 << 11` | `0x800` |
| `beforeRemoveLiquidity` | `1 << 9` | `0x200` |
| `beforeSwap` | `1 << 7` | `0x080` |
| `afterSwap` | `1 << 6` | `0x040` |
| **OR-sum** | | **`0x0AC0`** |

Deployed hook (Unichain Sepolia): `0x23C3da7CF53862Fd38640100D4FB764bE2d2cac0`

```
last 16 bits  = 0xcac0
mask (14 bits)= 0x3FFF
0xcac0 & 0x3FFF = 0x0AC0   ✓ exact match
```

`BEFORE_SWAP_RETURNS_DELTA` / `AFTER_SWAP_RETURNS_DELTA` are **off**, and the hook returns
`ZERO_DELTA` / `int128(0)` — v4 reverts if a hook returns a non-zero delta without those
flags, so the no-delta design is enforced, not just intended.

### The directional fee actually takes effect

`beforeSwap` returns `fee | LPFeeLibrary.OVERRIDE_FEE_FLAG`. v4 only honours that override on a
**dynamic-fee pool** — `lib/v4-core/src/libraries/Hooks.sol`:

```solidity
if (key.fee.isDynamicFee()) lpFeeOverride = result.parseFee();   // else the override is ignored
```

`LambdaHook.configurePool` therefore hard-requires it:

```solidity
if (!LPFeeLibrary.isDynamicFee(key.fee)) revert NotDynamicFee();
```

Constants don't collide: `DYNAMIC_FEE_FLAG = 0x800000`, `OVERRIDE_FEE_FLAG = 0x400000`, and the
directional fee maxes at ~23,000 pips (base 3000 + surcharge cap 20000) ≪ `MAX_LP_FEE` (1e6).

`beforeSwap` is `view`, so a router/quoter simulation never reverts on a state write — the hook
is cleanly **router-quotable**, and `previewFee(key, zeroForOne)` returns the exact fee a swap
would pay off-chain.

### Delta is exact, not approximated

`DeltaMath._amount0` reproduces Uniswap's own `SqrtPriceMath.getAmount0Delta(a, b, L, false)`
bit-for-bit:

```
L · 2^96 · (√b − √a) / (√b · √a)      rounding down
```

with correct regime handling (above range → 0 token0; below range → clamp to the lower edge).
This is cross-checked against v4's function in `contracts/test/DeltaMath.t.sol` (fuzzed).

---

## ② Reactive Network — the cross-chain brain

Checked against `lib/reactive-lib/src/{interfaces,abstract-base}`.

| Lambda usage | reactive-lib definition | Match |
|---|---|---|
| `service.subscribe(chainId, hook, topic0, IGNORE, IGNORE, IGNORE)` | `ISubscriptionService.subscribe(uint256,address,uint256,uint256,uint256,uint256)` | ✓ 6 args |
| `function react(LogRecord calldata log) external vmOnly` | `IReactive.react(LogRecord)` + `AbstractReactive.vmOnly` | ✓ |
| `emit Callback(destChainId, hedger, gasLimit, payload)` | `IReactive.Callback(uint256,address,uint64 gas_limit,bytes)` | ✓ (`gasLimit` is `uint64`) |
| `log.chain_id / _contract / topic_0 / topic_1 / topic_2 / data` | fields on `IReactive.LogRecord` | ✓ |
| `authorizedSenderOnly` on the hedger | `AbstractPayer.senders[msg.sender]` ACL, seeded by `AbstractCallback(callbackSender)` | ✓ |

**Event decode is correct.** The hook emits
`HedgeRequested(bytes32 indexed id, uint64 indexed nonce, uint256 targetSize, uint256 liveDelta,
uint160 sqrtPriceX96, uint256 timestamp)`. In the ReactVM:

- `HEDGE_TOPIC0 = keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)")`
- `topic_1` → `poolId`, `topic_2` → `nonce` (both indexed)
- `data` → `abi.decode(..., (uint256, uint256, uint160, uint256))`, taking `targetSize` and
  `sqrtPriceX96` and correctly discarding `liveDelta` + `timestamp`.

**Auth is layered.** The cross-chain payload carries an `address(0)` RVM-id placeholder the
relayer fills in; it is **not trusted**. Authorization is (a) the callback-proxy ACL
(`authorizedSenderOnly`) and (b) a strictly-increasing per-pool nonce re-checked on the
destination — replays and out-of-order callbacks are dropped on both legs.

### Mainnet readiness — confirmed by Reactive Network

HyperEVM testnet (998) is not a supported Reactive callback destination; only mainnet (999)
is. Per Reactive Network's team, the supported path is to prove callbacks on any other
supported testnet — which Lambda does on Unichain Sepolia, end-to-end. Their guidance:
*"if the setup works, it'll definitely also work once deployed on HyperEVM mainnet."* Going
live is therefore a configuration change only — `DESTINATION_CHAIN_ID 1301 → 999` and the
HyperEVM callback proxy — with **no contract code change**.

---

## ③ Hyperliquid — the perp hedge (CoreWriter)

Checked against the official CoreWriter spec
([docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore)).

**Precompile:** `ICoreWriter(0x3333…3333).sendRawAction(bytes)` — verified live on-chain on
HyperEVM (not a mock).

**Raw-action header:** 1 version byte + 3 action-id bytes (big-endian) + ABI-encoded args.
`CoreWriterLib.encodeLimitOrder` builds exactly that:

```solidity
abi.encodePacked(ENCODING_VERSION /*0x01*/, bytes3(ACTION_LIMIT_ORDER /*1*/), abi.encode(...));
// → 0x01 000001 <abi tuple>
```

**Limit-order fields (action ID 1)** — spec vs. `CoreWriterLib.LimitOrder`:

| # | Spec field | Spec type | Lambda field | Type | Match |
|---|---|---|---|---|---|
| 1 | asset | uint32 | `asset` | uint32 | ✓ |
| 2 | isBuy | bool | `isBuy` | bool | ✓ |
| 3 | limitPx | uint64 | `limitPx` | uint64 | ✓ |
| 4 | sz | uint64 | `sz` | uint64 | ✓ |
| 5 | reduceOnly | bool | `reduceOnly` | bool | ✓ |
| 6 | encodedTif | uint8 | `tif` | uint8 | ✓ |
| 7 | cloid | uint128 | `cloid` | uint128 | ✓ |

**TIF encoding:** `1 = Alo, 2 = Gtc, 3 = Ioc` → `CoreWriterLib.TIF_ALO/TIF_GTC/TIF_IOC` ✓.

**Scaling** (`limitPx = px·1e8`, `sz = sz·1e8 / 10^(6−szDecimals)`) is **externalized** to the
owner-set per-market `pxScaleWad` / `szScaleWad` in `LambdaHedger.configureMarket`, because
`szDecimals` differs per asset. This is genuine per-asset calibration kept in storage — tunable
without redeploying — not a hard-coded guess. The byte framing is unit-tested exactly in
`contracts/test/CoreWriterLib.t.sol` against a `MockCoreWriter` mirroring the precompile.

---

## ④ Deploy scripts ↔ on-chain config

- `DeployUnichain` mines exactly `BEFORE_ADD_LIQUIDITY | BEFORE_REMOVE_LIQUIDITY | BEFORE_SWAP |
  AFTER_SWAP`, initializes the pool with `DYNAMIC_FEE` (`0x800000`), and its computed
  `HedgeRequested` topic equals `LambdaReactive.HEDGE_TOPIC0`.
- `DeployReactive` is fully env-driven: promoting the loop to mainnet is `DESTINATION_CHAIN_ID=999`
  + `HEDGER` = the real `LambdaHedger` — **same script, no rewrite**.
- The reason leg ③ runs against a `LambdaHedgeReceiver` on testnet rather than the real hedger is
  purely external: Reactive's testnet does not list HyperEVM testnet (998) as a destination. This
  was **confirmed directly with the Reactive Network team**, who advised proving the callback on a
  supported testnet (Lambda uses Unichain Sepolia) and confirmed the proven setup carries over to
  HyperEVM mainnet unchanged.
- Fixed system addresses are constants and match the vendored libs: CoreWriter `0x33…33`,
  Reactive service `0x…fffFfF` (= `AbstractReactive.SERVICE_ADDR`), dynamic-fee `0x800000`
  (= `LPFeeLibrary.DYNAMIC_FEE_FLAG`).

---

## How to reproduce

```bash
forge build --sizes      # clean, no warnings; LambdaHook < 24,576 bytes
forge test               # full unit/invariant suite (fork tests self-skip offline)

# Run the loop against the LIVE contracts on a local fork — no gas, no faucet
# (see FORK_TESTING.md): real swap → live hook emits HedgeRequested → reactive
# routes → live receiver records it.
export UNICHAIN_SEPOLIA_RPC=https://sepolia.unichain.org
forge test --match-path 'contracts/test/fork/LambdaForkE2E.t.sol' -vvv

# Verify the live cross-chain delivery (no setup beyond cast):
cast call 0x36C7AA315e4Cd8aB7E8CADfbD5B10A3Fb03c2E0C \
  "hedge(bytes32)((uint64,uint64,uint256,uint160))" \
  0x92fcee81621f08f93eb2e42cbb5e42d969459a5e41cda459b329cbbd0ec4373b \
  --rpc-url https://sepolia.unichain.org
```

Every claim above is checkable from this repo plus the linked docs.
