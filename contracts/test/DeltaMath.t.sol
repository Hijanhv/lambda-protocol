// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeltaMath} from "../src/libraries/DeltaMath.sol";
import {SqrtPriceMath} from "v4-core/src/libraries/SqrtPriceMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @notice Property and fuzz tests for {DeltaMath}.
/// @dev The headline guarantee: our exact `lpDelta` reproduces Uniswap's own audited
///      `SqrtPriceMath.getAmount0Delta` across the whole tick range. The economic
///      helpers are checked for their stated bounds and monotonicity.
contract DeltaMathTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_LIQ = uint256(type(uint96).max); // keeps amount0 well within uint256

    // ─────────────────────────────────────────────────────────────────────────
    // lpDelta — exact, cross-checked against Uniswap
    // ─────────────────────────────────────────────────────────────────────────

    /// In range, lpDelta must equal token0 held between current price and the upper bound,
    /// i.e. exactly Uniswap's getAmount0Delta(sqrtP, sqrtPb, L, roundDown).
    function testFuzz_lpDelta_matchesUniswapReference(int256 tl, int256 tu, int256 tc, uint256 l) public pure {
        int24 tickLower = int24(bound(tl, TickMath.MIN_TICK, TickMath.MAX_TICK - 2));
        int24 tickUpper = int24(bound(tu, tickLower + 1, TickMath.MAX_TICK));
        int24 tickCur = int24(bound(tc, tickLower, tickUpper - 1)); // strictly inside, below upper
        uint128 liquidity = uint128(bound(l, 1, MAX_LIQ));

        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        uint160 sqrtP = TickMath.getSqrtPriceAtTick(tickCur);

        uint256 got = DeltaMath.lpDelta(liquidity, sqrtP, sqrtA, sqrtB);
        uint256 expected = SqrtPriceMath.getAmount0Delta(sqrtP, sqrtB, liquidity, false);
        assertEq(got, expected, "in-range delta must match Uniswap getAmount0Delta");
    }

    /// Below the range the position is entirely token0 (max delta = full-range amount0).
    function testFuzz_lpDelta_belowRange_isFullToken0(int256 tl, int256 tu, int256 tc, uint256 l) public pure {
        int24 tickLower = int24(bound(tl, TickMath.MIN_TICK + 1, TickMath.MAX_TICK - 1));
        int24 tickUpper = int24(bound(tu, tickLower + 1, TickMath.MAX_TICK));
        int24 tickCur = int24(bound(tc, TickMath.MIN_TICK, tickLower)); // at or below lower
        uint128 liquidity = uint128(bound(l, 1, MAX_LIQ));

        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        uint160 sqrtP = TickMath.getSqrtPriceAtTick(tickCur);

        uint256 got = DeltaMath.lpDelta(liquidity, sqrtP, sqrtA, sqrtB);
        uint256 full = SqrtPriceMath.getAmount0Delta(sqrtA, sqrtB, liquidity, false);
        assertEq(got, full, "below range must equal full-range token0");
    }

    /// Above the range the position is entirely token1 — zero ETH delta.
    function testFuzz_lpDelta_aboveRange_isZero(int256 tl, int256 tu, int256 tc, uint256 l) public pure {
        int24 tickLower = int24(bound(tl, TickMath.MIN_TICK, TickMath.MAX_TICK - 2));
        int24 tickUpper = int24(bound(tu, tickLower + 1, TickMath.MAX_TICK - 1));
        int24 tickCur = int24(bound(tc, tickUpper, TickMath.MAX_TICK)); // at or above upper
        uint128 liquidity = uint128(bound(l, 1, MAX_LIQ));

        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);
        uint160 sqrtP = TickMath.getSqrtPriceAtTick(tickCur);

        assertEq(DeltaMath.lpDelta(liquidity, sqrtP, sqrtA, sqrtB), 0, "above range must be zero");
    }

    /// Delta is non-increasing in price: as ETH rises, the pool has already sold ETH.
    function testFuzz_lpDelta_monotonicNonIncreasing(int256 tl, int256 tu, int256 c1, int256 c2, uint256 l)
        public
        pure
    {
        int24 tickLower = int24(bound(tl, TickMath.MIN_TICK, TickMath.MAX_TICK - 2));
        int24 tickUpper = int24(bound(tu, tickLower + 1, TickMath.MAX_TICK));
        int24 tickA = int24(bound(c1, tickLower, tickUpper - 1));
        int24 tickB = int24(bound(c2, tickLower, tickUpper - 1));
        if (tickA > tickB) (tickA, tickB) = (tickB, tickA); // tickA <= tickB  =>  priceA <= priceB
        uint128 liquidity = uint128(bound(l, 1, MAX_LIQ));

        uint160 sqrtA = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtB = TickMath.getSqrtPriceAtTick(tickUpper);

        uint256 dLow = DeltaMath.lpDelta(liquidity, TickMath.getSqrtPriceAtTick(tickA), sqrtA, sqrtB);
        uint256 dHigh = DeltaMath.lpDelta(liquidity, TickMath.getSqrtPriceAtTick(tickB), sqrtA, sqrtB);
        assertGe(dLow, dHigh, "delta must not increase with price");
    }

    /// @dev External wrapper so the library revert happens one frame below the cheatcode.
    function callLpDeltaBadRange() external pure returns (uint256) {
        return DeltaMath.lpDelta(1e18, uint160(1 << 96), uint160(2 << 96), uint160(1 << 96)); // a > b
    }

    function test_lpDelta_revertsOnBadRange() public {
        vm.expectRevert(DeltaMath.InvalidRange.selector);
        this.callLpDeltaBadRange();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // hedgeSize & shouldRehedge
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_hedgeSize_scalesByRatio(uint256 delta0, uint256 hWad) public pure {
        delta0 = bound(delta0, 0, 1e30);
        hWad = bound(hWad, 0, WAD); // 0..100%
        uint256 size = DeltaMath.hedgeSize(delta0, hWad);
        assertLe(size, delta0, "partial hedge cannot exceed delta");
        assertEq(size, delta0 * hWad / WAD, "hedge size = delta * h");
    }

    function test_hedgeSize_fullHedgeIsIdentity() public pure {
        assertEq(DeltaMath.hedgeSize(123_456e18, WAD), 123_456e18);
    }

    function test_hedgeSize_default65Percent() public pure {
        // Lambda's default h = 0.65 keeps liquidation risk near 1.4% (Hane 2026).
        assertEq(DeltaMath.hedgeSize(100e18, 0.65e18), 65e18);
    }

    function testFuzz_shouldRehedge_matchesDriftThreshold(uint256 target, uint256 live, uint256 tau) public pure {
        target = bound(target, 0, 1e30);
        live = bound(live, 0, 1e30);
        tau = bound(tau, 0, 1e30);
        uint256 drift = live > target ? live - target : target - live;
        assertEq(DeltaMath.shouldRehedge(target, live, tau), drift > tau);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // gamma slippage — bounded by |Γ|·τ²/8 within a τ/2 band
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_gammaSlip_withinBoundForHalfBand(uint256 liq, uint256 price, uint256 tau, uint256 dPrice)
        public
        pure
    {
        uint256 liquidityWad = bound(liq, WAD, 1e27);
        uint256 priceWad = bound(price, WAD, 1e25);
        uint256 tauWad = bound(tau, 1e12, priceWad / 10);
        uint256 dPriceWad = bound(dPrice, 0, tauWad / 2); // price stays within the τ/2 half-band

        uint256 slip = DeltaMath.gammaSlip(liquidityWad, priceWad, dPriceWad);
        uint256 bound_ = DeltaMath.gammaSlipBound(liquidityWad, priceWad, tauWad);
        // exact in reals; allow a hair for independent integer-rounding of the two expressions
        assertLe(slip, bound_ + bound_ / 1e6 + 1, "gamma slip must stay under |gamma|*tau^2/8");
    }

    function testFuzz_gammaSlip_monotonicInMove(uint256 liq, uint256 price, uint256 d1, uint256 d2) public pure {
        uint256 liquidityWad = bound(liq, WAD, 1e27);
        uint256 priceWad = bound(price, WAD, 1e25);
        uint256 a = bound(d1, 0, 1e23);
        uint256 b = bound(d2, 0, 1e23);
        if (a > b) (a, b) = (b, a);
        assertLe(
            DeltaMath.gammaSlip(liquidityWad, priceWad, a),
            DeltaMath.gammaSlip(liquidityWad, priceWad, b),
            "slip grows with the price move"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // tauOptimal — τ* ≈ (3σ²LC/P)^{1/3}
    // ─────────────────────────────────────────────────────────────────────────

    function test_tauOptimal_saneMagnitude() public pure {
        // σ=3%/day, L=100 ETH, P=$3,500, C=$5  (spec §1.4 example)
        uint256 tau = DeltaMath.tauOptimal(0.03e18, 100e18, 3500e18, 5e18);
        assertGt(tau, 0.001e18, "tau too small");
        assertLt(tau, 1e18, "tau under 1 ETH for this size");
    }

    function test_tauOptimal_increasesWithVolatility() public pure {
        uint256 lo = DeltaMath.tauOptimal(0.02e18, 100e18, 3500e18, 5e18);
        uint256 hi = DeltaMath.tauOptimal(0.06e18, 100e18, 3500e18, 5e18);
        assertGt(hi, lo, "more volatility => wider re-hedge band");
    }

    function test_tauOptimal_decreasesWithPrice() public pure {
        uint256 cheap = DeltaMath.tauOptimal(0.03e18, 100e18, 2000e18, 5e18);
        uint256 dear = DeltaMath.tauOptimal(0.03e18, 100e18, 8000e18, 5e18);
        assertGt(cheap, dear, "higher price => tighter band (in token0 units)");
    }

    function test_tauOptimal_increasesWithCost() public pure {
        uint256 lo = DeltaMath.tauOptimal(0.03e18, 100e18, 3500e18, 2e18);
        uint256 hi = DeltaMath.tauOptimal(0.03e18, 100e18, 3500e18, 20e18);
        assertGt(hi, lo, "pricier re-hedges => re-hedge less often => wider band");
    }
}
