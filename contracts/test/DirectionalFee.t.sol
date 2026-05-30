// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DirectionalFee} from "../src/libraries/DirectionalFee.sol";

/// @notice Property/fuzz tests for {DirectionalFee}. The guarantees that matter for an LVR
///         defense: the fee stays within bounds, the trend-continuing (informed) side is
///         never cheaper than the mean-reverting side, the surcharge grows with drift up to
///         its cap, and the asymmetry is symmetric under flipping both drift and direction.
contract DirectionalFeeTest is Test {
    uint24 internal constant MAX = 1_000_000;

    // Sensible Lambda defaults for the concrete-value checks.
    uint24 internal constant BASE = 3000; // 0.30%
    uint24 internal constant MIN = 500; // 0.05%
    uint24 internal constant CAP = 20_000; // 2.0%
    uint256 internal constant SENS = 50; // pips per tick

    function _bounded(uint24 base, uint24 min_, uint24 cap, uint256 sens, int24 drift)
        internal
        pure
        returns (uint24, uint24, uint24, uint256, int24)
    {
        min_ = uint24(bound(min_, 0, MAX));
        base = uint24(bound(base, min_, MAX)); // min ≤ base ≤ MAX
        cap = uint24(bound(cap, 0, MAX));
        sens = bound(sens, 0, 1e6);
        return (base, min_, cap, sens, drift);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // bounds
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_feeWithinBounds(uint24 base, uint24 min_, uint24 cap, uint256 sens, int24 drift, bool z)
        public
        pure
    {
        (base, min_, cap, sens, drift) = _bounded(base, min_, cap, sens, drift);
        uint24 f = DirectionalFee.asymmetricFee(base, min_, cap, sens, drift, z);
        assertGe(f, min_, "fee never below the floor");
        assertLe(f, MAX, "fee never above MAX_LP_FEE");
    }

    function testFuzz_surchargeCapped(uint256 sens, int24 drift, uint24 cap) public pure {
        sens = bound(sens, 0, 1e9);
        cap = uint24(bound(cap, 0, MAX));
        assertLe(DirectionalFee.surcharge(sens, drift, cap), cap, "surcharge never exceeds cap");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // asymmetry
    // ─────────────────────────────────────────────────────────────────────────

    /// The trend-continuing side is always at least as expensive as the mean-reverting side.
    function testFuzz_informedSideCostsMore(uint24 base, uint24 min_, uint24 cap, uint256 sens, int24 drift)
        public
        pure
    {
        (base, min_, cap, sens, drift) = _bounded(base, min_, cap, sens, drift);
        vm.assume(drift != 0);

        // drift > 0 ⇒ continuing side is !zeroForOne (price up); drift < 0 ⇒ zeroForOne.
        bool continuingIsZeroForOne = drift < 0;
        uint24 informed = DirectionalFee.asymmetricFee(base, min_, cap, sens, drift, continuingIsZeroForOne);
        uint24 benign = DirectionalFee.asymmetricFee(base, min_, cap, sens, drift, !continuingIsZeroForOne);
        assertGe(informed, benign, "informed side is never cheaper");
    }

    /// Flipping both the drift sign and the swap direction must give the same fee — the model
    /// depends only on the relationship between drift and direction, not their absolute signs.
    function testFuzz_signSymmetry(uint24 base, uint24 min_, uint24 cap, uint256 sens, int24 drift, bool z)
        public
        pure
    {
        (base, min_, cap, sens, drift) = _bounded(base, min_, cap, sens, drift);
        vm.assume(drift != type(int24).min); // -drift must be representable
        uint24 a = DirectionalFee.asymmetricFee(base, min_, cap, sens, drift, z);
        uint24 b = DirectionalFee.asymmetricFee(base, min_, cap, sens, -drift, !z);
        assertEq(a, b, "fee is invariant under flipping both signs");
    }

    /// Surcharge is non-decreasing in |drift| (until the cap clamps it).
    function testFuzz_surchargeMonotonicInDrift(uint256 sens, int24 d1, int24 d2) public pure {
        sens = bound(sens, 0, 1e4);
        d1 = int24(bound(d1, 0, 8_388_607)); // [0, MAX_TICK-ish], non-negative
        d2 = int24(bound(d2, 0, 8_388_607));
        if (d1 > d2) (d1, d2) = (d2, d1);
        assertLe(
            DirectionalFee.surcharge(sens, d1, type(uint24).max),
            DirectionalFee.surcharge(sens, d2, type(uint24).max),
            "surcharge grows with drift magnitude"
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // concrete behaviour
    // ─────────────────────────────────────────────────────────────────────────

    function test_flatPriceChargesBase() public pure {
        assertEq(DirectionalFee.asymmetricFee(BASE, MIN, CAP, SENS, 0, true), BASE);
        assertEq(DirectionalFee.asymmetricFee(BASE, MIN, CAP, SENS, 0, false), BASE);
    }

    function test_upDriftSurchargesBuysDiscountsSells() public pure {
        int24 drift = 100; // price 100 ticks above reference
        // buy (price up, !zeroForOne) = continuing ⇒ base + 100*50 = 3000 + 5000.
        assertEq(DirectionalFee.asymmetricFee(BASE, MIN, CAP, SENS, drift, false), BASE + 5000);
        // sell (price down, zeroForOne) = reverting ⇒ base - 5000, floored at MIN.
        assertEq(DirectionalFee.asymmetricFee(BASE, MIN, CAP, SENS, drift, true), MIN);
    }

    function test_downDriftSurchargesSellsDiscountsBuys() public pure {
        int24 drift = -100;
        // sell (price down, zeroForOne) = continuing ⇒ surcharge.
        assertEq(DirectionalFee.asymmetricFee(BASE, MIN, CAP, SENS, drift, true), BASE + 5000);
        // buy (price up, !zeroForOne) = reverting ⇒ floored.
        assertEq(DirectionalFee.asymmetricFee(BASE, MIN, CAP, SENS, drift, false), MIN);
    }

    function test_surchargeRespectsCap() public pure {
        int24 drift = 10_000; // 10000*50 = 500000 pips, far over the 20000 cap
        assertEq(DirectionalFee.asymmetricFee(BASE, MIN, CAP, SENS, drift, false), BASE + CAP);
    }
}
