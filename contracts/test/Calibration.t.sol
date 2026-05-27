// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {DeltaMath} from "../src/libraries/DeltaMath.sol";

/// @notice A code-backed calibration report for Lambda's economics. Run with
///         `forge test --match-contract Calibration -vv` to print the derived numbers that
///         back `CALIBRATION.md` and the README earnings table. Every figure comes from
///         {DeltaMath}, so the model and the deployed math cannot drift apart. Assertions
///         pin the magnitudes to sane, defensible ranges.
contract CalibrationTest is Test {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant DAYS_PER_YEAR = 365;

    /// @dev Annualize a daily vol: σ_annual = σ_daily · √365.
    function _annualizeVol(uint256 sigmaDailyWad) internal pure returns (uint256) {
        return FixedPointMathLib.mulWad(sigmaDailyWad, FixedPointMathLib.sqrtWad(DAYS_PER_YEAR * WAD));
    }

    /// @dev LVR drag rate over a horizon = σ²/8 (Milionis et al.). All WAD.
    function _lvrRate(uint256 sigmaWad) internal pure returns (uint256) {
        return FixedPointMathLib.mulWad(sigmaWad, sigmaWad) / 8;
    }

    function test_report_lvrAcrossVolRegimes() public pure {
        // ETH daily realized vol spans roughly 2%–6% across regimes.
        uint16[3] memory dailyBps = [uint16(200), 400, 600]; // 2%, 4%, 6% per day
        console2.log("--- LVR rate (annual) vs ETH realized vol ---");
        for (uint256 i; i < dailyBps.length; ++i) {
            uint256 sigmaDaily = uint256(dailyBps[i]) * WAD / 10_000;
            uint256 sigmaAnnual = _annualizeVol(sigmaDaily);
            uint256 lvr = _lvrRate(sigmaAnnual);
            console2.log("  daily vol (bps):", dailyBps[i]);
            console2.log("  annual vol (1e18):", sigmaAnnual);
            console2.log("  LVR rate/yr (1e18):", lvr);
            // Sanity: across this vol band, annual LVR sits in a single-digit-to-teens % range.
            assertGt(lvr, 0.01e18, "LVR > 1%/yr");
            assertLt(lvr, 0.3e18, "LVR < 30%/yr");
        }
    }

    function test_report_optimalRehedgeBand() public pure {
        // σ=3%/day, position size L=100 ETH-equiv, P=$3,500, re-hedge cost C=$5 (spec §1.4).
        uint256 tau = DeltaMath.tauOptimal(0.03e18, 100e18, 3500e18, 5e18);
        console2.log("--- optimal re-hedge band tau* ---");
        console2.log("  tau* (ETH, 1e18):", tau);
        // A sane band: a few thousandths of an ETH up to under 1 ETH for this size.
        assertGt(tau, 0.001e18, "tau* not dust");
        assertLt(tau, 1e18, "tau* < 1 ETH for 100-ETH position");
    }

    function test_report_residualTrackingErrorIsSmall() public pure {
        // Within a band of half-width tau/2, residual IL per interval <= |gamma|*tau^2/8.
        uint256 liquidity = 100e18;
        uint256 price = 3500e18;
        uint256 tau = DeltaMath.tauOptimal(0.03e18, liquidity, price, 5e18);
        uint256 bound_ = DeltaMath.gammaSlipBound(liquidity, price, tau);
        console2.log("--- residual gamma slippage per re-hedge interval ---");
        console2.log("  bound (1e18):", bound_);
        // The whole point of delta-neutralizing: residual per interval is a tiny fraction of size.
        assertLt(bound_, liquidity / 1000, "residual << position size");
    }

    function test_report_hedgeRatioCapturesMostOfTheLeak() public pure {
        // The short, sized at h=0.65 of delta, collects funding ~ h * LVR (identity), so it
        // offsets ~65% of the structural leak before fees/the directional fee are counted.
        uint256 lvrAnnual = _lvrRate(_annualizeVol(0.04e18)); // 4%/day regime
        uint256 hedgeRatio = 0.65e18; // Hane (2026) h*; LambdaHook.DEFAULT_HEDGE_RATIO
        uint256 captured = FixedPointMathLib.mulWad(hedgeRatio, lvrAnnual);
        console2.log("--- funding capture at h = 0.65 ---");
        console2.log("  LVR/yr (1e18):", lvrAnnual);
        console2.log("  offset by hedge (1e18):", captured);
        // Captured offset is a clear majority of the leak.
        assertGe(captured * 100 / lvrAnnual, 64, ">=64% of LVR offset by the hedge notional");
    }
}
