// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LambdaHedger} from "../src/LambdaHedger.sol";
import {CoreWriterLib} from "../src/libraries/CoreWriterLib.sol";
import {ICoreWriter, CORE_WRITER} from "../src/interfaces/ICoreWriter.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Capture-only stand-in for the CoreWriter precompile (mirrors the fork test's mock).
contract MockCoreWriter is ICoreWriter {
    bytes public lastAction;

    function sendRawAction(bytes calldata data) external {
        lastAction = data;
    }
}

/// @title HedgerCalibration
/// @notice Pins the **mainnet** size/price calibration of {LambdaHedger} to Hyperliquid's wire
///         rule: CoreWriter limit orders carry `limitPx` and `sz` as **10^8 × the human value**
///         (confirmed against Hyperliquid's "Interacting with HyperCore" docs).
///
/// @dev    WHY THIS TEST EXISTS. The hedger is generic framing: it converts a token0-WAD size
///         and a Uniswap sqrt price into L1 integer units through two owner-set scales
///         (`szScaleWad`, `pxScaleWad`). The values used in the fork test and the testnet
///         runbook (`szScaleWad = 1`, `pxScaleWad = 1e18`) are byte-capture placeholders — they
///         make `sz`/`limitPx` *non-zero* so the framing can be asserted, but they do **not**
///         satisfy the 10^8 wire rule, so they would mis-size a real order by ~10^8×.
///
///         This test derives and locks the scales a real **WETH(18)/USDC(6)** pool needs, and
///         proves a hedge at a known price/size encodes to the exact Hyperliquid integers:
///
///           • size:  short 5 WETH → sz = 5 × 10^8
///           • price: ETH = $3000  → limitPx ≈ 3000 × 10^8 (minus taker slippage)
///
///         Derivation (token0 = WETH 18-dec, token1 = USDC 6-dec):
///           sizeWad is human × 1e18, and  sz = sizeWad · szScaleWad / 1e18 = human · szScaleWad.
///           To hit human · 1e8  ⇒  **szScaleWad = 1e8**.
///           midPriceWad = (sqrtP/2^96)^2 · 1e18, which for a raw 18/6 ratio equals human · 1e6,
///           and  limitPx = midPriceWad · pxScaleWad / 1e18 = human · 1e6 · pxScaleWad / 1e18.
///           To hit human · 1e8  ⇒  **pxScaleWad = 1e20**.
contract HedgerCalibrationTest is Test {
    LambdaHedger internal hedger;

    bytes32 internal constant POOL = keccak256("WETH/USDC");
    uint32 internal constant ASSET = 1; // ETH-PERP L1 index (illustrative)
    uint16 internal constant SLIPPAGE_BPS = 50; // 0.5% taker allowance

    // The mainnet calibration this test proves correct (see contract NatSpec).
    uint256 internal constant SZ_SCALE_WAD = 1e8;
    uint256 internal constant PX_SCALE_WAD = 1e20;

    uint16 internal constant MAX_BPS = 10_000;

    function setUp() public {
        // callbackSender = owner = this test ⇒ authorized to drive applyHedge + configure.
        hedger = new LambdaHedger(address(this), address(this));
        hedger.configureMarket(POOL, ASSET, SZ_SCALE_WAD, PX_SCALE_WAD, SLIPPAGE_BPS, CoreWriterLib.TIF_IOC);
        vm.etch(CORE_WRITER, address(new MockCoreWriter()).code);
    }

    /// @dev sqrtPriceX96 for a raw token1/token0 ratio: sqrt(ratio) · 2^96, with ratio in Q192.
    function _sqrtPriceX96(uint256 amount1Raw, uint256 amount0Raw) internal pure returns (uint160) {
        uint256 ratioX192 = FullMath.mulDiv(amount1Raw, 1 << 192, amount0Raw);
        return uint160(FixedPointMathLib.sqrt(ratioX192));
    }

    function test_mainnetScales_encodeOrderInHyperliquidWireUnits() public {
        // ETH = $3000 on a WETH(18)/USDC(6) pool: raw ratio = 3000·1e6 USDC per 1·1e18 WETH.
        uint160 sqrtP = _sqrtPriceX96(3000 * 1e6, 1e18);

        // The hedger sees mid ≈ 3000 · 1e6 (raw-ratio · 1e18); the calibration must turn that
        // into the Hyperliquid wire price of 3000 · 1e8. Anchor independently to that target.
        uint256 preSlipPx = FullMath.mulDiv(hedger.midPriceWad(sqrtP), PX_SCALE_WAD, 1e18);
        assertApproxEqRel(preSlipPx, uint256(3000) * 1e8, 1e15, "px scale must yield ~3000e8"); // 0.1%

        // Open a 5 WETH short (token0 WAD) and capture the order the hedger fires.
        uint256 targetSize = 5e18;
        hedger.applyHedge(address(0), POOL, 1, targetSize, sqrtP);
        (uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 tif,) =
            _decode(MockCoreWriter(CORE_WRITER).lastAction());

        // Size: exactly 5 × 10^8, the Hyperliquid wire unit for 5 contracts.
        assertEq(sz, uint64(5 * 1e8), "sz must be human size x 1e8");

        // Price: mid biased down for a taker sell, in 10^8 wire units (~3000e8 minus slippage).
        uint64 expectedPx = uint64(FullMath.mulDiv(preSlipPx, MAX_BPS - SLIPPAGE_BPS, MAX_BPS));
        assertEq(limitPx, expectedPx, "limitPx must match the 1e8-scaled, slippage-biased mid");
        assertApproxEqRel(uint256(limitPx), uint256(3000) * 1e8, 1e16, "limitPx ~ 3000e8 +/- 1%");

        // Framing sanity: a fresh short is a non-reduce-only taker sell on the configured asset.
        assertEq(asset, ASSET, "asset index");
        assertFalse(isBuy, "opening a short sells");
        assertFalse(reduceOnly, "growing the short is not reduce-only");
        assertEq(tif, CoreWriterLib.TIF_IOC, "taker time-in-force");
    }

    /// @dev Strip the 4-byte (version + action-id) prefix and decode the order tuple.
    function _decode(bytes memory action)
        internal
        pure
        returns (uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 tif, uint128 cloid)
    {
        bytes memory body = new bytes(action.length - 4);
        for (uint256 i = 0; i < body.length; i++) {
            body[i] = action[i + 4];
        }
        return abi.decode(body, (uint32, bool, uint64, uint64, bool, uint8, uint128));
    }
}
