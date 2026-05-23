// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "v4-core/src/libraries/FixedPoint96.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @title DeltaMath
/// @notice Concentrated-liquidity delta and hedge-sizing math for the Lambda protocol.
/// @dev Two families of functions, deliberately kept separate:
///
///      1. EXACT, settlement-grade math in Uniswap's Q64.96 convention
///         (`lpDelta`, `hedgeSize`, `shouldRehedge`). These drive the real hedge,
///         so they mirror Uniswap's own `SqrtPriceMath.getAmount0Delta` rounding
///         and are cross-checked against it in the test suite.
///
///      2. ECONOMIC ESTIMATES in WAD (1e18) fixed point (`gammaAbs`, `gammaSlip`,
///         `gammaSlipBound`, `tauOptimal`). These size thresholds and bound the
///         residual tracking error; WAD precision is appropriate for them. They
///         assume an 18-decimal volatile token (e.g. WETH), which matches Lambda's
///         ETH/USDC target market.
///
///      Math references (see README + spec §1.1-§1.6):
///        x(P) = L·(1/√P − 1/√P_b)            token0 inventory  (Uniswap v3 Core, Appendix)
///        Δ_LP(P) = x(P)                       LP spot delta equals token0 inventory
///        Γ_LP = −L / (2·P^{3/2})              LP gamma (short gamma)
///        residual ≈ ½·|Γ|·δP²                 gamma slippage of a delta-only hedge
///        τ* ≈ (3·σ²·L·C / P)^{1/3}            optimal re-hedge band
library DeltaMath {
    uint256 internal constant WAD = 1e18;

    error InvalidRange();

    // ─────────────────────────────────────────────────────────────────────────
    // Exact delta (Q64.96)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Token0 (volatile asset) inventory of a concentrated-liquidity position,
    ///         which equals the position's spot delta. Regime-aware across the range.
    /// @param liquidity      Position liquidity `L`.
    /// @param sqrtPriceX96   Current price as a Q64.96 sqrt price.
    /// @param sqrtPriceAX96  Lower bound of the range as a Q64.96 sqrt price.
    /// @param sqrtPriceBX96  Upper bound of the range as a Q64.96 sqrt price.
    /// @return delta0        Amount of token0 held (token0's native units). This is the
    ///                       quantity Lambda must short to neutralize first-order IL.
    function lpDelta(uint128 liquidity, uint160 sqrtPriceX96, uint160 sqrtPriceAX96, uint160 sqrtPriceBX96)
        internal
        pure
        returns (uint256 delta0)
    {
        if (sqrtPriceAX96 == 0 || sqrtPriceAX96 > sqrtPriceBX96) revert InvalidRange();

        uint160 s = sqrtPriceX96;
        // Above the range: position is entirely token1 (the numéraire), so zero ETH delta.
        if (s >= sqrtPriceBX96) return 0;
        // Below the range: position is entirely token0, valued at the lower edge.
        if (s < sqrtPriceAX96) s = sqrtPriceAX96;
        // In range: token0 held between the current price and the upper bound.
        return _amount0(s, sqrtPriceBX96, liquidity);
    }

    /// @dev token0 between two sqrt prices, rounding down — identical to Uniswap's
    ///      `SqrtPriceMath.getAmount0Delta(a, b, L, false)`:
    ///      L · 2^96 · (b − a) / (b · a).
    function _amount0(uint160 sqrtA, uint160 sqrtB, uint128 liquidity) private pure returns (uint256) {
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = uint256(sqrtB) - uint256(sqrtA);
        return FullMath.mulDiv(numerator1, numerator2, sqrtB) / sqrtA;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hedge sizing & drift
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Target short size = hedge ratio · LP delta. Lambda defaults `h = 0.65e18`
    ///         (Hane 2026 optimal ratio under perp liquidation risk).
    /// @param delta0          LP delta from {lpDelta} (token0 units).
    /// @param hedgeRatioWad   Hedge ratio `h` in WAD; 1e18 == full hedge.
    function hedgeSize(uint256 delta0, uint256 hedgeRatioWad) internal pure returns (uint256) {
        return FixedPointMathLib.mulWad(delta0, hedgeRatioWad);
    }

    /// @notice True when the live delta has drifted past the threshold and a re-hedge is due.
    /// @param targetDelta  The hedge size currently on the books.
    /// @param liveDelta    The position's delta right now.
    /// @param tau          Drift threshold in token0 units (see {tauOptimal}).
    function shouldRehedge(uint256 targetDelta, uint256 liveDelta, uint256 tau) internal pure returns (bool) {
        uint256 drift = liveDelta > targetDelta ? liveDelta - targetDelta : targetDelta - liveDelta;
        return drift > tau;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Economic estimates (WAD; assume 18-decimal volatile token)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Magnitude of LP gamma, |Γ| = L / (2·P^{3/2}). All values WAD.
    function gammaAbs(uint256 liquidityWad, uint256 priceWad) internal pure returns (uint256) {
        // P^{3/2} = P · √P
        uint256 p32 = FixedPointMathLib.mulWad(priceWad, FixedPointMathLib.sqrtWad(priceWad));
        return FixedPointMathLib.divWad(liquidityWad, 2 * p32);
    }

    /// @notice Realized gamma slippage of a delta-only hedge over a price move `dPrice`:
    ///         ½·|Γ|·δP². The irreducible quadratic cost of hedging discretely. All WAD.
    function gammaSlip(uint256 liquidityWad, uint256 priceWad, uint256 dPriceWad) internal pure returns (uint256) {
        uint256 g = gammaAbs(liquidityWad, priceWad);
        uint256 dp2 = FixedPointMathLib.mulWad(dPriceWad, dPriceWad);
        return FixedPointMathLib.mulWad(g, dp2) / 2;
    }

    /// @notice Upper bound on per-interval gamma slippage, |Γ|·τ²/8, when the price stays
    ///         within a band of half-width τ/2 between re-hedges (spec §1.5). All WAD.
    function gammaSlipBound(uint256 liquidityWad, uint256 priceWad, uint256 tauWad) internal pure returns (uint256) {
        uint256 g = gammaAbs(liquidityWad, priceWad);
        uint256 t2 = FixedPointMathLib.mulWad(tauWad, tauWad);
        return FixedPointMathLib.mulWad(g, t2) / 8;
    }

    /// @notice Optimal re-hedge band τ* ≈ (3·σ²·L·C / P)^{1/3}, balancing re-hedge cost
    ///         against gamma slippage (spec §1.4). All values WAD; result in token0 units.
    /// @param sigmaWad        Realized volatility σ (e.g. daily), WAD.
    /// @param liquidityWad    Position liquidity / size, WAD.
    /// @param priceWad        Current price `P`, WAD.
    /// @param costWad         Dollar cost `C` of one re-hedge (callback gas + taker fee), WAD.
    function tauOptimal(uint256 sigmaWad, uint256 liquidityWad, uint256 priceWad, uint256 costWad)
        internal
        pure
        returns (uint256)
    {
        uint256 sigma2 = FixedPointMathLib.mulWad(sigmaWad, sigmaWad);
        uint256 inner = FixedPointMathLib.mulWad(3 * WAD, sigma2); // 3σ²
        inner = FixedPointMathLib.mulWad(inner, liquidityWad); // ·L
        inner = FixedPointMathLib.mulWad(inner, costWad); // ·C
        inner = FixedPointMathLib.divWad(inner, priceWad); // /P
        return FixedPointMathLib.cbrtWad(inner);
    }
}
