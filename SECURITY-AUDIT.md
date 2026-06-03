# Security audit — LambdaHook (Uniswap v4 `v4-security-foundations`)

This is a self-audit of `LambdaHook` performed with Uniswap's **official** v4 hook-security
skill, `v4-security-foundations` (installed via `npx skills add Uniswap/uniswap-ai`). Every one
of the skill's twelve catalogued vulnerability classes was checked line-by-line against the
deployed hook, and the skill's dynamic-analysis step (high-run fuzzing + invariants) was run.

**Scope:** `contracts/src/LambdaHook.sol` and its libraries (`DeltaMath`, `DirectionalFee`),
with the settlement path through `unlockCallback`.

**Headline:** no findings at Medium or above. The hook sits in the **lowest-risk v4 design class**
— a sole-LP vault that enables **no** return-delta permissions and never modifies the swap curve,
which structurally sidesteps the entire NoOp / delta-theft attack family.

---

## Vulnerability catalog results

| # | Class (skill catalog) | Severity | Result | Why |
|---|---|---|---|---|
| 1 | NoOp rug pull (`beforeSwapReturnDelta`) | CRITICAL | ✅ Safe | All four return-delta flags are `false`; `beforeSwap` returns `BeforeSwapDeltaLibrary.ZERO_DELTA`. The attack requires `beforeSwapReturnDelta`, which is off. |
| 2 | Missing PoolManager verification | CRITICAL | ✅ Safe | `beforeAddLiquidity`, `beforeRemoveLiquidity`, `beforeSwap`, `afterSwap`, and `unlockCallback` all carry `onlyPoolManager` (reverts `NotPoolManager`). |
| 3 | Delta accounting mismatch | CRITICAL | ✅ Safe | `afterSwap` returns `int128(0)`. The only `take`/`settle` is inside `unlockCallback`, balanced against the `modifyLiquidity` delta with `Slippage` bounds. Invariant `invariant_sharesSumToTotal` holds under fuzzing. |
| 4 | Reentrancy via external calls | HIGH | ✅ Safe | `deposit`/`withdraw` are `nonReentrant` (Solady). The sole external call, `_notifyShares` → trusted `Funding`, runs **after** share-state updates (checks-effects-interactions). |
| 5 | Unbounded loop DoS | HIGH | ✅ Safe | No loops in any hook callback. |
| 6 | Liquidity lock | HIGH | ✅ Safe | `beforeRemoveLiquidity` only gates `sender == address(this)`; there is no time-lock or admin flag that can trap LP funds. `withdraw` is always callable by share holders. |
| 7 | Single-block price manipulation | MEDIUM | ✅ Mitigated | The directional fee references an **EMA-smoothed** tick (`refTick`, `emaWeightBps`), not raw spot. The hook makes no value transfer on price — it emits a hedge *signal* and returns a fee bounded by `minFeePips`/`maxSurchargePips`. The off-chain hedge is independently slippage-bounded. |
| 8 | Missing slippage protection | MEDIUM | ✅ Safe | `deposit`/`withdraw` enforce `amount{0,1}Max` / `amount{0,1}Min` (revert `Slippage`). The hedger enforces `slippageBps` on the limit price. |
| 9 | Fee-on-transfer token mismatch | MEDIUM | ✅ Safe-by-revert | Settlement uses v4's `sync`→`transferFrom`→`settle`; a FoT token under-settles and the unlock reverts (`CurrencyNotSettled`) rather than mis-accounting. Target market is WETH/USDC (non-FoT). |
| 10 | Hardcoded addresses | LOW | ✅ Safe | `poolManager` is an immutable constructor arg. CoreWriter (`0x33…33`) and the Reactive service (`0x…fffFfF`) are legitimate fixed system precompiles/contracts, not the anti-pattern. |
| 11 | Missing event emissions | LOW | ✅ Safe | Every state change emits (`PoolConfigured`, `FeeParamsUpdated`, `HedgeParamsUpdated`, `ShareCallbackSet`, `Deposited`, `Withdrawn`, `HedgeRequested`). |
| 12 | Unchecked return values | LOW | ✅ Safe | Token movements use Solady `SafeTransferLib`; PoolManager interactions are checked through the unlock/settle flow. |

---

## Permissions review (skill §3)

| Permission | Enabled | Justification | Risk |
|---|---|---|---|
| `beforeAddLiquidity` | ✅ | Enforce the sole-LP vault invariant (reject all LPs but the hook) | Low — view-only gate |
| `beforeRemoveLiquidity` | ✅ | Same gate on removal | Low — view-only gate |
| `beforeSwap` | ✅ | Return the directional dynamic-fee override (`view`) | Low — fee only, curve untouched, router-quotable |
| `afterSwap` | ✅ | Recompute exact delta, maybe emit `HedgeRequested`, nudge fee EMA | Low — returns `int128(0)` |
| all `*ReturnDelta` | ❌ | Not needed — protection is off-curve | **None — avoids the critical NoOp class** |
| all others | ❌ | Unused lifecycle points revert `HookNotImplemented` | None |

The deployed address `0x23C3…cac0` encodes exactly these four bits (`0xcac0 & 0x3FFF = 0x0AC0`),
which v4's `validateHookPermissions` enforces at construction. See `VERIFICATION.md` §①.

---

## Dynamic analysis (skill's testing step)

```
forge test                                   → 127 unit/invariant passing, warning-free build
forge test (+ live forks: UNICHAIN+HYPEREVM) → 134 / 134 passing (7 fork tests replay all 3 legs on real chain state)
FOUNDRY_FUZZ_RUNS=10000 forge test (core)    → 57 / 57 passing, 0 invariant failures
```

Invariant suites exercised: `FundingInvariant` (rewards-per-share accounting), and
`InsuranceVaultInvariant` (shares ≤ total), plus fuzzed `DeltaMath` cross-checks against
Uniswap's own `SqrtPriceMath.getAmount0Delta`.

> **Static analysis (Slither):** not run in this environment (no Python/`pip` available).
> Recommended before mainnet: `slither . --detect all` and `solhint 'contracts/**/*.sol'`.

---

## Hardening notes (not findings — for the mainnet threat model)

These do not affect testnet safety and are consistent with the README's commitment to a full
professional review before any mainnet deployment:

1. **Single-step ownership.** `Ownable.transferOwnership` is one-step; a two-step
   propose/accept (or timelock) is recommended for the mainnet owner key.
2. **Trusted share-callback.** `Funding` is an owner-set callback invoked during `deposit`/
   `withdraw`. It is our own contract and must remain non-reverting; a defensive `try/catch`
   could be considered so a callback bug can never block an LP withdrawal.
3. **Slither/Mythril pass** + the transitive frontend-dependency advisories should be cleared
   before mainnet (already listed under *Gating before mainnet* in the README).

---

## Risk assessment

| Category | Risk | Notes |
|---|---|---|
| Access control | **Low** | All callbacks PoolManager-gated; admin `onlyOwner` |
| Delta accounting | **Low** | No return-delta perms; settle/take balanced; invariant-tested |
| Reentrancy | **Low** | `nonReentrant` + CEI; only trusted external call |
| DoS | **Low** | No loops, no unbounded state |
| **Overall** | **Low (Tier 1 — self-audit)** | Matches the README roadmap: professional audit gated before mainnet |

Audited with Uniswap `v4-security-foundations` against `contracts/src/LambdaHook.sol`.
Reproduce: `npx skills add Uniswap/uniswap-ai` then review against this hook; `forge test`.
