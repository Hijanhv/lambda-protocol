// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LambdaHedger} from "../src/LambdaHedger.sol";
import {CoreWriterLib} from "../src/libraries/CoreWriterLib.sol";
import {ICoreWriter, CORE_WRITER} from "../src/interfaces/ICoreWriter.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @notice Records every raw action so tests can decode the order the hedger actually sent.
contract MockCoreWriter is ICoreWriter {
    bytes public lastAction;
    uint256 public calls;

    function sendRawAction(bytes calldata data) external {
        lastAction = data;
        calls++;
    }
}

/// @notice Tests for {LambdaHedger} -- the money leg. Focus is the decision logic: it trades
///         only the difference to the target short, enforces auth + nonce monotonicity, and
///         frames a correct CoreWriter order (decoded back out of the mock precompile).
contract LambdaHedgerTest is Test {
    LambdaHedger internal hedger;
    MockCoreWriter internal core;

    bytes32 internal constant POOL = keccak256("ETH/USDC");
    uint32 internal constant ASSET = 1;
    uint16 internal constant SLIPPAGE_BPS = 50; // 0.5%
    address internal constant RVM = address(0xA11CE); // stand-in ReactVM id
    uint160 internal sqrtP11;

    function setUp() public {
        // Etch the mock at the canonical precompile address the library calls.
        core = new MockCoreWriter();
        vm.etch(CORE_WRITER, address(core).code);

        // callbackSender = this test, so it is the authorized caller; owner = this test too.
        hedger = new LambdaHedger(address(this), address(this));
        // szScaleWad = 1 -> sz(L1 lots) = sizeWad / 1e18; pxScaleWad = 1e18 -> px ~ mid.
        // szDecimals = 0 for this test market (integer lots).
        hedger.configureMarket(POOL, ASSET, 1, 1e18, 0, SLIPPAGE_BPS, CoreWriterLib.TIF_IOC);

        sqrtP11 = TickMath.getSqrtPriceAtTick(0); // price 1.0
    }

    // ─────────────────────────────────────────────────────────────────────────
    // order decoding helper
    // ─────────────────────────────────────────────────────────────────────────

    function _lastOrder()
        internal
        view
        returns (uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 tif, uint128 cloid)
    {
        bytes memory data = MockCoreWriter(CORE_WRITER).lastAction();
        bytes memory body = new bytes(data.length - 4);
        for (uint256 i = 0; i < body.length; i++) {
            body[i] = data[i + 4];
        }
        return abi.decode(body, (uint32, bool, uint64, uint64, bool, uint8, uint128));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // opening / growing / shrinking / closing
    // ─────────────────────────────────────────────────────────────────────────

    function test_applyHedge_opensShort() public {
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);

        assertEq(hedger.shortSize(POOL), 100e18, "short opened to target");
        assertEq(MockCoreWriter(CORE_WRITER).calls(), 1, "one order sent");

        (uint32 asset, bool isBuy,, uint64 sz, bool reduceOnly, uint8 tif,) = _lastOrder();
        assertEq(asset, ASSET, "right asset");
        assertFalse(isBuy, "opening a short sells");
        assertFalse(reduceOnly, "opening is not reduce-only");
        assertEq(sz, 100, "100e18 wad -> 100 L1 lots at szScale 1");
        assertEq(tif, CoreWriterLib.TIF_IOC, "taker fill");
    }

    function test_applyHedge_growsShort() public {
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
        hedger.applyHedge(RVM, POOL, 2, 160e18, sqrtP11);

        assertEq(hedger.shortSize(POOL), 160e18, "short grown to new target");
        (, bool isBuy,, uint64 sz, bool reduceOnly,,) = _lastOrder();
        assertFalse(isBuy, "growing still sells");
        assertFalse(reduceOnly, "growing is not reduce-only");
        assertEq(sz, 60, "trades only the 60-lot difference");
    }

    function test_applyHedge_shrinksShort() public {
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
        hedger.applyHedge(RVM, POOL, 2, 40e18, sqrtP11);

        assertEq(hedger.shortSize(POOL), 40e18, "short reduced to target");
        (, bool isBuy,, uint64 sz, bool reduceOnly,,) = _lastOrder();
        assertTrue(isBuy, "shrinking buys back");
        assertTrue(reduceOnly, "shrinking is reduce-only");
        assertEq(sz, 60, "trades only the 60-lot difference");
    }

    function test_applyHedge_closesShort() public {
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
        hedger.applyHedge(RVM, POOL, 2, 0, sqrtP11);

        assertEq(hedger.shortSize(POOL), 0, "short fully closed");
        (, bool isBuy,,, bool reduceOnly,,) = _lastOrder();
        assertTrue(isBuy, "closing buys back");
        assertTrue(reduceOnly, "closing is reduce-only -- cannot flip long");
    }

    function test_applyHedge_noopWhenTargetUnchanged() public {
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
        uint256 callsAfterOpen = MockCoreWriter(CORE_WRITER).calls();

        hedger.applyHedge(RVM, POOL, 2, 100e18, sqrtP11);
        assertEq(MockCoreWriter(CORE_WRITER).calls(), callsAfterOpen, "no order when already on target");
        assertEq(hedger.shortSize(POOL), 100e18, "short unchanged");
    }

    function test_applyHedge_subLotDiffIsRecordedWithoutOrder() public {
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
        uint256 callsBefore = MockCoreWriter(CORE_WRITER).calls();

        // +0.5e18 wad with szScale 1 => 0 lots => no order, but the target is latched.
        hedger.applyHedge(RVM, POOL, 2, 100e18 + 0.5e18, sqrtP11);
        assertEq(MockCoreWriter(CORE_WRITER).calls(), callsBefore, "sub-lot move sends no order");
        assertEq(hedger.shortSize(POOL), 100e18 + 0.5e18, "intent still recorded");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // pricing
    // ─────────────────────────────────────────────────────────────────────────

    function test_midPrice_isOneAtPrice1to1() public view {
        assertEq(hedger.midPriceWad(sqrtP11), 1e18, "mid is exactly 1.0 at the 1:1 tick");
    }

    function test_sellPricesBelowMid_buyPricesAboveMid() public {
        // Sell (open short) -- limit below mid.
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
        (,, uint64 sellPx,,,,) = _lastOrder();
        assertLt(sellPx, 1e18, "sell limit sits below mid");
        assertApproxEqRel(sellPx, uint256(1e18) * (10_000 - SLIPPAGE_BPS) / 10_000, 1e12, "~ mid*(1-slip)");

        // Buy (reduce) -- limit above mid.
        hedger.applyHedge(RVM, POOL, 2, 50e18, sqrtP11);
        (,, uint64 buyPx,,,,) = _lastOrder();
        assertGt(buyPx, 1e18, "buy limit sits above mid");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // auth & nonce
    // ─────────────────────────────────────────────────────────────────────────

    function test_applyHedge_revertsOnStaleNonce() public {
        hedger.applyHedge(RVM, POOL, 5, 100e18, sqrtP11);
        vm.expectRevert(LambdaHedger.StaleNonce.selector);
        hedger.applyHedge(RVM, POOL, 5, 80e18, sqrtP11); // equal nonce replays
        vm.expectRevert(LambdaHedger.StaleNonce.selector);
        hedger.applyHedge(RVM, POOL, 4, 80e18, sqrtP11); // older nonce
    }

    function test_applyHedge_revertsForUnauthorizedSender() public {
        vm.prank(address(0xBADBAD));
        vm.expectRevert(); // authorizedSenderOnly
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
    }

    function test_applyHedge_revertsIfMarketNotConfigured() public {
        vm.expectRevert(LambdaHedger.MarketNotConfigured.selector);
        hedger.applyHedge(RVM, keccak256("UNCONFIGURED"), 1, 100e18, sqrtP11);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // admin
    // ─────────────────────────────────────────────────────────────────────────

    function test_configureMarket_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hedger.configureMarket(POOL, ASSET, 1, 1e18, 0, SLIPPAGE_BPS, CoreWriterLib.TIF_IOC);
    }

    function test_configureMarket_rejectsBadParams() public {
        vm.expectRevert(LambdaHedger.InvalidParams.selector);
        hedger.configureMarket(POOL, ASSET, 0, 1e18, 0, SLIPPAGE_BPS, CoreWriterLib.TIF_IOC); // szScale 0
        vm.expectRevert(LambdaHedger.InvalidParams.selector);
        hedger.configureMarket(POOL, ASSET, 1, 1e18, 0, 10_001, CoreWriterLib.TIF_IOC); // slippage > 100%
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bug 3 regression: price sig figs
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Verify that limitPx never has more than 5 significant figures.
    ///      Uses a pxScaleWad that produces a deliberately "ugly" price.
    function test_limitPrice_hasAtMostFiveSigFigs() public {
        // pxScaleWad = 3e18 → at 1:1 sqrtPrice, mid = 1e18, px = 3e18 (just 1 sig fig — already fine).
        // Use a scale that yields a multi-digit raw price: 3_141_592e12 WAD scale → px ≈ 3.14e18.
        bytes32 pool2 = keccak256("FIVE_SIG_FIG_POOL");
        hedger.configureMarket(pool2, ASSET, 1, 3_141_592_000_000_000_000, 0, SLIPPAGE_BPS, CoreWriterLib.TIF_IOC);
        hedger.applyHedge(RVM, pool2, 1, 100e18, sqrtP11);

        (,, uint64 px,,,,) = _lastOrder();
        // Count significant figures: divide out trailing zeros, count remaining digits.
        uint256 p = uint256(px);
        while (p % 10 == 0 && p > 0) p /= 10;
        uint256 sigFigs = 0;
        uint256 tmp = p;
        while (tmp > 0) { tmp /= 10; sigFigs++; }
        assertLe(sigFigs, 5, "limitPx must have at most 5 significant figures");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bug 4 regression: position reconciliation
    // ─────────────────────────────────────────────────────────────────────────

    function test_reconcile_correctsShortSize() public {
        hedger.applyHedge(RVM, POOL, 1, 100e18, sqrtP11);
        assertEq(hedger.shortSize(POOL), 100e18, "precondition");

        // Simulate a partial fill: actual size on HyperCore is only 60e18.
        vm.expectEmit(true, false, false, true, address(hedger));
        emit LambdaHedger.PositionReconciled(POOL, 100e18, 60e18);
        hedger.reconcile(POOL, 60e18);

        assertEq(hedger.shortSize(POOL), 60e18, "shortSize corrected");
    }

    function test_reconcile_revertsForUnconfiguredMarket() public {
        vm.expectRevert(LambdaHedger.MarketNotConfigured.selector);
        hedger.reconcile(keccak256("UNCONFIGURED"), 0);
    }

    function test_reconcile_onlyOwner() public {
        vm.prank(address(0xBADBAD));
        vm.expectRevert();
        hedger.reconcile(POOL, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Bug 5 regression: margin transfer
    // ─────────────────────────────────────────────────────────────────────────

    function test_fundMargin_sendsCorrectAction() public {
        vm.expectEmit(false, false, false, true, address(hedger));
        emit LambdaHedger.MarginFunded(5_000_000); // 5 USDC in 1e6 units
        hedger.fundMargin(5_000_000);

        bytes memory sent = MockCoreWriter(CORE_WRITER).lastAction();
        // Header: version=1, action=7
        assertEq(uint8(sent[0]), 1, "version byte");
        assertEq(uint8(sent[1]), 0, "action hi");
        assertEq(uint8(sent[2]), 0, "action mid");
        assertEq(uint8(sent[3]), 7, "action lo == 7 (usdClassTransfer)");
        // Decode body: (uint64 ntl, bool toPerp)
        bytes memory body = new bytes(sent.length - 4);
        for (uint256 i = 0; i < body.length; i++) body[i] = sent[i + 4];
        (uint64 ntl, bool toPerp) = abi.decode(body, (uint64, bool));
        assertEq(ntl, 5_000_000, "ntl");
        assertTrue(toPerp, "toPerp=true for fundMargin");
    }

    function test_withdrawMargin_sendsCorrectAction() public {
        hedger.withdrawMargin(2_000_000);
        bytes memory sent = MockCoreWriter(CORE_WRITER).lastAction();
        bytes memory body = new bytes(sent.length - 4);
        for (uint256 i = 0; i < body.length; i++) body[i] = sent[i + 4];
        (, bool toPerp) = abi.decode(body, (uint64, bool));
        assertFalse(toPerp, "toPerp=false for withdrawMargin");
    }

    function test_marginFunctions_onlyOwner() public {
        vm.prank(address(0xBADBAD));
        vm.expectRevert();
        hedger.fundMargin(1);
        vm.prank(address(0xBADBAD));
        vm.expectRevert();
        hedger.withdrawMargin(1);
    }

    function test_checkpointFunding_emitsAndIsGated() public {
        vm.expectEmit(true, false, false, false, address(hedger));
        emit LambdaHedger.FundingCheckpoint(RVM, block.timestamp);
        hedger.checkpointFunding(RVM);

        vm.prank(address(0xBADBAD));
        vm.expectRevert();
        hedger.checkpointFunding(RVM);
    }
}
