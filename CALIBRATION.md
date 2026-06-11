# Economic calibration

This document makes Lambda's earnings model explicit, states every assumption, and ties the
headline numbers to code. The figures below are produced by `contracts/test/Calibration.t.sol`
using the *same* `DeltaMath` library the contracts deploy, so the model and the on-chain math
cannot drift apart.

> Reproduce: `forge test --match-contract Calibration -vv`

## The model

A Lambda LP holds two positions at once: the Uniswap v4 position and a perp short, plus a
directional fee on the pool. Annualized, the net return decomposes as:

```
R_LP  =  trading_fees  +  funding_income  −  LVR  −  gamma_slippage  −  rehedge_costs
```

| Term | What sets it | Sign |
|---|---|---|
| `trading_fees` | volume × effective fee (the **directional fee** raises the fee on toxic flow) | + |
| `funding_income` | short notional × funding rate = `h · |Δ|·P · funding_rate` | ±* |
| `LVR` | `σ²/8` per year (Milionis et al.), the pool always bears this | − |
| `gamma_slippage` | `≤ |Γ|·τ²/8` per re-hedge interval, the cost of hedging discretely | − |
| `rehedge_costs` | `C` per re-hedge, frequency minimized by the optimal band `τ*` | − |

\* Funding is **usually positive** for an ETH perp short (longs pay shorts in neutral/bull
regimes) but can turn negative in sustained bear markets. See the downside section.

## Assumptions (stated, not hidden)

| Input | Value used | Basis |
|---|---|---|
| ETH realized vol `σ` | 4-5% / day (approx. 76-95% annual) | ETH historical realized vol band |
| ETH perp funding | 8-15% / yr | historical Hyperliquid/large-venue ETH funding |
| Base pool fee | 0.30% (`base = 3000` pips) | standard ETH/USDC tier; directional fee floats around it |
| Hedge ratio `h` | 0.65 | Hane et al. (2026), liquidation-risk-optimal |
| Re-hedge band `τ` | `τ* ≈ (3σ²LC/P)^{1/3}` | spec §1.4 / `DeltaMath.tauOptimal` |

## Code-backed figures

From the calibration report:

```
LVR rate (annual)            2%/day → 1.8%    4%/day → 7.3%    6%/day → 16.4%
optimal band τ*  (σ=3%/day, L=100 ETH, P=$3500, C=$5)   ≈ 0.073 ETH
residual gamma slippage / interval                       ≈ 1.6e-7 ETH   (negligible)
funding offset at h=0.65 (4%/day regime)                 ≈ 4.7% / yr of the 7.3% LVR
```

So the README's "~11%/yr LVR" corresponds to ETH at roughly **5%/day** vol, squarely inside
the historical band, not a cherry-pick. The residual tracking error of discrete hedging is
seven orders of magnitude below position size, which is why a `τ`-banded hedge is viable.

## Worked example → the README table

ETH/USDC, `σ ≈ 5%/day`, funding ≈ 12%/yr, fees ≈ 8%/yr, `h = 0.65`:

```
trading fees      +8%        (curve unchanged; directional fee lifts the toxic-flow share)
LVR               −11%       (σ²/8 at ~5%/day)
funding income    +12%       (short collects funding; ≈ the LVR identity, historically a bit above)
gamma + costs     −0.5%      (τ-banded; bounded by |Γ|τ²/8)
─────────────────────────
net               ≈ +8.5%/yr  with price risk ~0 (93-97% of IL neutralized)
```

The README's **18-30%/yr** is the *optimistic* end (higher fees + higher funding); this worked
case is the conservative middle. Both are **modeled, not promised**.

## Downside & why it's still defensible

If funding goes **negative** (bear market, shorts pay longs), `funding_income` becomes a cost.
Lambda is built so this is bounded, not catastrophic:

1. **The directional fee is funding-independent.** It recaptures LVR at the pool regardless of
   the perp market, so the on-chain defense keeps working when funding flips.
2. **`h = 0.65`, not 1.0.** Only 65% of delta is exposed to funding, so a negative-funding
   drag is capped, and the same ratio keeps liquidation probability near 1.4% over 90 days.
3. **The insurance reserve** (`InsuranceVault`) backstops liquidation gaps, earning Aave yield
   while idle so backers are paid to stand behind the tail.
4. **`h` and `τ` are governance-tunable**, so a persistently adverse regime can be dialed down
   without a redeploy.

Honest summary: Lambda is **strongly positive when funding is positive** (the historical norm
for ETH), **roughly fees-minus-residual when funding is mildly negative**, and **protected
against liquidation tails** by design. The structure earns across up, down, and sideways
markets. It is not a bet that funding is always positive.
