// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title DirectionalFee
/// @notice Asymmetric, flow-direction-aware swap fee for the Lambda hook — the on-pool half
///         of Lambda's LVR defense (the off-pool half is the perp hedge).
///
/// @dev    The model is Nezlobin's directional fee. An AMM bleeds value to arbitrageurs who
///         trade in the direction that drags the pool price toward the (moved) external price.
///         If the pool price has drifted *up* from a smoothed reference, the next price-up
///         trade is the likely-informed, trend-continuing one; the price-down trade is the
///         benign, mean-reverting one. So we **surcharge the trend-continuing side and
///         discount the mean-reverting side**, sized by how far price has drifted:
///
///            drift            = currentTick − referenceTick        (signed, EMA reference)
///            surcharge(pips)  = min(maxSurcharge, sensitivity·|drift|)
///            continuing side  → baseFee + surcharge   (capped at MAX_LP_FEE)
///            reverting side   → baseFee − surcharge   (floored at minFee)
///
///         A swap "continues" the drift when its price impact has the same sign as the drift:
///         in Uniswap's convention a `zeroForOne` swap pushes price down, `!zeroForOne` up.
///
///         Fees are in pips (1e-6); `sensitivity` is pips of surcharge per tick of drift.
///         This is pure math, kept separate from the hook so it can be fuzzed for its bounds
///         and symmetry the same way {DeltaMath} is.
library DirectionalFee {
    /// @notice Uniswap's maximum LP fee (100%), in pips.
    uint24 internal constant MAX_LP_FEE = 1_000_000;

    /// @notice The directional add-on for a given drift, capped at `maxSurchargePips`.
    /// @param sensitivityPipsPerTick  Pips of surcharge per tick of drift.
    /// @param driftTicks              Signed price drift from the reference, in ticks.
    /// @param maxSurchargePips        Upper bound on the surcharge.
    function surcharge(uint256 sensitivityPipsPerTick, int24 driftTicks, uint24 maxSurchargePips)
        internal
        pure
        returns (uint24)
    {
        // Widen before negating: `-driftTicks` would overflow int24 at its minimum.
        int256 d = int256(driftTicks);
        uint256 mag = uint256(d < 0 ? -d : d);
        uint256 raw = sensitivityPipsPerTick * mag;
        // The branch only narrows `raw` when it is below `maxSurchargePips` (a uint24), so safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        return raw < maxSurchargePips ? uint24(raw) : maxSurchargePips;
    }

    /// @notice The asymmetric fee an incoming swap should pay.
    /// @param baseFeePips         Neutral fee charged when price is at the reference.
    /// @param minFeePips          Floor for the discounted (mean-reverting) side.
    /// @param maxSurchargePips    Cap on the directional add-on.
    /// @param sensitivityPipsPerTick  Pips of surcharge per tick of drift.
    /// @param driftTicks          Signed drift = currentTick − referenceTick.
    /// @param zeroForOne          Swap direction; `true` pushes price down, `false` up.
    /// @return feePips            Fee for this swap, always within [minFee, MAX_LP_FEE].
    function asymmetricFee(
        uint24 baseFeePips,
        uint24 minFeePips,
        uint24 maxSurchargePips,
        uint256 sensitivityPipsPerTick,
        int24 driftTicks,
        bool zeroForOne
    ) internal pure returns (uint24 feePips) {
        if (driftTicks == 0) {
            return baseFeePips < minFeePips ? minFeePips : baseFeePips;
        }

        uint24 s = surcharge(sensitivityPipsPerTick, driftTicks, maxSurchargePips);

        // Continuing the drift means the swap's price push matches the drift's sign.
        bool driftUp = driftTicks > 0;
        bool pushesPriceUp = !zeroForOne;
        if (driftUp == pushesPriceUp) {
            uint256 f = uint256(baseFeePips) + s; // surcharge the informed side
            // Narrowed only when f ≤ MAX_LP_FEE (1e6), well within uint24.
            // forge-lint: disable-next-line(unsafe-typecast)
            return f > MAX_LP_FEE ? MAX_LP_FEE : uint24(f);
        } else {
            uint24 f = baseFeePips > s ? baseFeePips - s : 0; // discount the benign side
            return f < minFeePips ? minFeePips : f;
        }
    }
}
