# Technical verification: Lambda Protocol

This document records a direct cross-check of Lambda's three partner integrations against
each chain's **authoritative source**: the vendored libraries that actually compile into the
contracts (`lib/v4-core`, `lib/reactive-lib`) and the official Hyperliquid CoreWriter docs.
The intent is that a judge can confirm the integrations are real and correct without taking
anything on faith.

**Status at time of writing:** `forge build` clean (no warnings), **142 tests across 16
suites** (incl. invariant fuzzing), 135 unit/invariant passing offline, plus 7 fork tests
that exercise all three legs against their real chains' state: legs ① + ③ on a Unichain
Sepolia fork and leg ② (the real `LambdaHedger` firing a CoreWriter short) on a HyperEVM
mainnet fork. The fork tests self-skip when no RPC is set. `LambdaHook` 14,393 bytes
(< 24,576 deploy limit).

---

## ① Uniswap v4: the hook

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
`ZERO_DELTA` / `int128(0)`; v4 reverts if a hook returns a non-zero delta without those
flags, so the no-delta design is enforced, not just intended.

### The directional fee actually takes effect

`beforeSwap` returns `fee | LPFeeLibrary.OVERRIDE_FEE_FLAG`. v4 only honours that override on a
**dynamic-fee pool** (`lib/v4-core/src/libraries/Hooks.sol`):

```solidity
if (key.fee.isDynamicFee()) lpFeeOverride = result.parseFee();   // else the override is ignored
```

`LambdaHook.configurePool` therefore hard-requires it:

```solidity
if (!LPFeeLibrary.isDynamicFee(key.fee)) revert NotDynamicFee();
```

Constants don't collide: `DYNAMIC_FEE_FLAG = 0x800000`, `OVERRIDE_FEE_FLAG = 0x400000`, and the
directional fee maxes at ~23,000 pips (base 3000 + surcharge cap 20000) ≪ `MAX_LP_FEE` (1e6).

`beforeSwap` is `view`, so a router/quoter simulation never reverts on a state write. The hook
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

## ② Reactive Network: the cross-chain brain

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
destination; replays and out-of-order callbacks are dropped on both legs.

### Mainnet readiness, confirmed by Reactive Network

HyperEVM testnet (998) is not a supported Reactive callback destination; only mainnet (999)
is. Per Reactive Network's team, the supported path is to prove callbacks on any other
supported testnet, which Lambda does on Unichain Sepolia, end-to-end. Their guidance:
*"if the setup works, it'll definitely also work once deployed on HyperEVM mainnet."* Promotion
to mainnet follows a documented checklist: point the Reactive leg at HyperEVM mainnet (`DESTINATION_CHAIN_ID=999`), set `invertedPair=true` for a USDC/WETH pool, use the calibrated price scales (`szScaleWad=1e8`, `pxScaleWad=1e20`), and call `fundMargin()` to seed perp margin. No contract rewrite.

---

## ③ Hyperliquid: the perp hedge (CoreWriter)

Checked against the official CoreWriter spec
([docs](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/interacting-with-hypercore)).

**Precompile:** `ICoreWriter(0x3333…3333).sendRawAction(bytes)`, verified live on-chain on
HyperEVM (not a mock).

**Raw-action header:** 1 version byte + 3 action-id bytes (big-endian) + ABI-encoded args.
`CoreWriterLib.encodeLimitOrder` builds exactly that:

```solidity
abi.encodePacked(ENCODING_VERSION /*0x01*/, bytes3(ACTION_LIMIT_ORDER /*1*/), abi.encode(...));
// → 0x01 000001 <abi tuple>
```

**Limit-order fields (action ID 1)**, spec vs. `CoreWriterLib.LimitOrder`:

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

**Scaling.** Hyperliquid wants `limitPx` and `sz` as **`10^8 × the human value`**. Lambda
**externalizes** this to the owner-set per-market `pxScaleWad` / `szScaleWad` in
`LambdaHedger.configureMarket`, because the asset's `szDecimals` differs per market. Genuine
per-asset calibration kept in storage, tunable without redeploying, not a hard-coded guess. The
verified scales for a **WETH(18) / USDC(6)** pool are `szScaleWad = 1e8`, `pxScaleWad = 1e20`,
**proven** in [`contracts/test/HedgerCalibration.t.sol`](contracts/test/HedgerCalibration.t.sol)
A 5-WETH short at $3000 encodes to exactly `sz = 5e8`, `limitPx ≈ 3000e8`. The byte framing is
unit-tested exactly in `contracts/test/CoreWriterLib.t.sol` against a `MockCoreWriter` mirroring
the precompile. (The fork-test placeholders `szScaleWad=1, pxScaleWad=1e18` only make the bytes
non-zero for capture; they are **not** mainnet-correct. See the deploy runbook.)

---

## ④ Deploy scripts ↔ on-chain config

- `DeployUnichain` mines exactly `BEFORE_ADD_LIQUIDITY | BEFORE_REMOVE_LIQUIDITY | BEFORE_SWAP |
  AFTER_SWAP`, initializes the pool with `DYNAMIC_FEE` (`0x800000`), and its computed
  `HedgeRequested` topic equals `LambdaReactive.HEDGE_TOPIC0`.
- `DeployReactive` is fully env-driven: promoting the loop to mainnet is `DESTINATION_CHAIN_ID=999`
  + `HEDGER` = the real `LambdaHedger`. **Same script, no rewrite.**
- The reason leg ③ runs against a `LambdaHedgeReceiver` on testnet rather than the real hedger is
  purely external: Reactive's testnet does not list HyperEVM testnet (998) as a destination. This
  was **confirmed directly with the Reactive Network team**, who advised proving the callback on a
  supported testnet (Lambda uses Unichain Sepolia) and confirmed the proven setup carries over to
  HyperEVM mainnet unchanged.
- Fixed system addresses are constants and match the vendored libs: CoreWriter `0x33…33`,
  Reactive service `0x…fffFfF` (= `AbstractReactive.SERVICE_ADDR`), dynamic-fee `0x800000`
  (= `LPFeeLibrary.DYNAMIC_FEE_FLAG`).

---

## ⑤ Testing methodology: the techniques UHI teaches, applied here

UHI's *"Testing your first hook"* lesson teaches three core approaches: **unit tests**,
**fuzzing** (with `bound()` and `vm.assume()`), and **forking inside tests**. Lambda's suite
uses **all of them**, and then goes further with invariant suites and live cross-chain forks.
Each is real and checkable in this repo:

| Technique UHI teaches | Where Lambda applies it |
|---|---|
| **Unit tests** (`test_…`, happy + sad paths) | every suite, e.g. `LambdaHedger.t.sol` (auth, nonce monotonicity, open/grow/shrink/close, sub-lot no-op) |
| **Fuzz with `bound()`** (clamp into a safe range) | `DirectionalFee.t.sol`, `FundingInvariant.t.sol` (fee params; share/funding amounts) |
| **Fuzz with `vm.assume()`** (reject invalid inputs) | `DirectionalFee.t.sol` (`drift != 0`; `-drift` representable) |
| **Forking inside tests** (`vm.createSelectFork`) | `contracts/test/fork/*`: legs ①+③ on a Unichain Sepolia fork, leg ② on a HyperEVM **mainnet** fork |
| **`Deployers` helper + `HookMiner`** | hook tests + deploy scripts mine the permission-bit address into the deployed contract |
| **Gas report / verbosity** (`--gas-report`, `-vv…`) | available on demand; `beforeSwap` is `view`, so quoting/swaps stay cheap |

Beyond the curriculum, Lambda adds **2 invariant suites** (Funding solvency, fee monotonicity,
each with 256-run × thousands-of-call fuzzing) and **live-fork integration across two real
chains in a single `forge test` run, a step past the single-chain unit test the lesson
covers. Totals: **142 tests / 16 suites**, 135 unit-and-invariant pass offline, 7 fork tests
replay all three legs against live chain state (all 7 pass with RPCs set; they self-skip
without).

Run the UHI-style commands directly:

```bash
forge test                                        # full suite (135 pass, 7 fork self-skip)
forge test --mc DirectionalFee                    # one fuzzed contract (bound() + vm.assume())
forge test --mc HedgerCalibration -vvv            # the mainnet CoreWriter wire-scale proof
forge test --mt test_fork_endToEndHedgeLoop -vvv  # the live cross-chain loop, with traces
forge test --gas-report                           # per-function gas
```

---

## ⑥ What being on testnet leaves unexercised (and how Lambda covers it)

Because Reactive's testnet can't reach HyperEVM (998) and a real perp needs real margin, a few
**mainnet-only behaviours are not live on testnet**. Lambda is explicit about this. None are
faked; each is either fork-proven now or scoped as audited-mainnet hardening:

| Not live on testnet | Why it can't be | How Lambda covers it today |
|---|---|---|
| The real CoreWriter **fill** on HyperCore | the order only fills on Hyperliquid's validators, which a fork can't run | the real `LambdaHedger` fires the **byte-exact** order on a HyperEVM-mainnet fork (asserted), and the precompile was probed live on-chain; the economic fill is proven on the mainnet deploy |
| **On-chain funding return** | bridging L1 funding back to LPs is an operational leg | `Funding.notifyFunding` is the authorized deposit point; automating the bridge + keeper is the headline post-mainnet roadmap item |
| **Position reconciliation** after partial fills *(audit item C)* | needs the HyperCore position precompile, which is mainnet-only | tracked as mainnet-hardening (would adopt `hyper-evm-lib`'s `PrecompileLib` there) |
| **Tick/lot price rounding** *(audit item B)* | depends on the live matching engine's per-asset `szDecimals` | documented; the wire-scale calibration is proven in `HedgerCalibration.t.sol` |
| **Perp margin** *(audit item D)* | the hedger's HyperCore account must hold USDC | pre-funded out-of-band on mainnet (≥ ~$10), documented in the deploy runbook |

This boundary is a deliberate, **research-backed scoping choice**, not a gap. The design
composes peer-reviewed work. Milionis (2022) gives the `σ²/8` loss the hedge recaptures,
Chitra & Diamandis (2025) prove Hyperliquid-class venues are *easy to delta-hedge*, and Hane
(2026) sets the liquidation-safe `h = 0.65`. Everything that can be proven without a live venue
is proven here (byte-exact orders, exact delta, fuzzed fee/funding invariants, the live
cross-chain loop); the parts that genuinely require a live venue are the ones, and the only
ones, deferred to the audited mainnet deploy.

---

## How to reproduce

```bash
forge build --sizes      # clean, no warnings; LambdaHook < 24,576 bytes
forge test               # full unit/invariant suite (fork tests self-skip offline)

# Run the loop against the LIVE contracts on a local fork (no gas, no faucet)
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
