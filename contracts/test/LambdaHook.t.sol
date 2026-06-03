// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {LambdaHook} from "../src/LambdaHook.sol";
import {DeltaMath} from "../src/libraries/DeltaMath.sol";

/// @notice Lifecycle tests for {LambdaHook} against a real v4 PoolManager.
/// @dev The vault owns the only position, so liquidity must flow through `deposit`/`withdraw`
///      — direct router liquidity is expected to revert. Swaps come from the standard swap
///      router (an outside trader, which the hook permits) and are what move the delta and
///      raise {HedgeRequested}. We assert on the hook's own state (nonce / hedgedDelta /
///      currentDelta) and, for the headline path, decode the emitted event.
contract LambdaHookTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    LambdaHook internal hook;
    PoolId internal id; // `key` is inherited from Deployers

    int24 internal constant TICK_LOWER = -600;
    int24 internal constant TICK_UPPER = 600;
    int24 internal constant TICK_SPACING = 60;
    uint24 internal constant FEE = LPFeeLibrary.DYNAMIC_FEE_FLAG; // directional fee requires dynamic

    uint128 internal constant DEPOSIT_LIQ = 1e21;
    // τ small relative to the position delta, so the first deposit and a moderate swap both
    // clear the band; widened per-test where we want the "no re-hedge" path.
    uint256 internal constant TAU = 1e15;

    // keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)")
    bytes32 internal constant HEDGE_SIG = keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)");

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Mine an address whose low bits encode exactly our three permissions, then etch
        // the hook there — this is what `validateHookPermissions` checks in the constructor.
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );
        address hookAddr = address(flags | (uint160(0x4444) << 144));
        deployCodeTo("LambdaHook.sol:LambdaHook", abi.encode(manager, address(this)), hookAddr);
        hook = LambdaHook(payable(hookAddr));

        (key, id) = initPool(currency0, currency1, IHooks(hookAddr), FEE, TICK_SPACING, SQRT_PRICE_1_1);

        // The vault pulls the LP's tokens via transferFrom, so the LP (this contract) approves it.
        MockERC20(Currency.unwrap(currency0)).approve(hookAddr, type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(hookAddr, type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _configure(uint256 tau) internal {
        hook.configurePool(key, TICK_LOWER, TICK_UPPER, tau, 0); // 0 ⇒ default h = 0.65
    }

    /// @dev The position's delta at the current pool price, computed independently of the hook.
    function _expectedDelta() internal view returns (uint256) {
        (uint160 sqrtP,,,) = manager.getSlot0(id);
        return DeltaMath.lpDelta(
            DEPOSIT_LIQ, sqrtP, TickMath.getSqrtPriceAtTick(TICK_LOWER), TickMath.getSqrtPriceAtTick(TICK_UPPER)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // deposit
    // ─────────────────────────────────────────────────────────────────────────

    function test_deposit_mintsSharesAndTracksLiquidity() public {
        _configure(TAU);

        uint256 bal0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 bal1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        (uint256 shares, uint256 amount0, uint256 amount1) =
            hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        // First deposit: shares anchored 1:1 to liquidity.
        assertEq(shares, DEPOSIT_LIQ, "first deposit shares == liquidity");
        assertEq(hook.sharesOf(key, address(this)), DEPOSIT_LIQ, "shares credited to LP");

        LambdaHook.PoolState memory ps = hook.poolState(key);
        assertEq(ps.liquidity, DEPOSIT_LIQ, "vault liquidity tracked");
        assertEq(ps.totalShares, DEPOSIT_LIQ, "total shares tracked");

        // Both legs were actually paid in.
        assertGt(amount0, 0, "paid token0");
        assertGt(amount1, 0, "paid token1");
        assertEq(bal0Before - MockERC20(Currency.unwrap(currency0)).balanceOf(address(this)), amount0, "token0 debited");
        assertEq(bal1Before - MockERC20(Currency.unwrap(currency1)).balanceOf(address(this)), amount1, "token1 debited");
    }

    function test_deposit_emitsFirstHedgeRequested() public {
        _configure(TAU);

        uint256 expectedDelta = _expectedDelta();
        uint256 expectedTarget = DeltaMath.hedgeSize(expectedDelta, hook.DEFAULT_HEDGE_RATIO());

        vm.recordLogs();
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        (bool found, uint64 nonce, uint256 targetSize, uint256 liveDelta) = _lastHedge();
        assertTrue(found, "HedgeRequested emitted on first deposit");
        assertEq(nonce, 1, "first signal is nonce 1");
        assertEq(liveDelta, expectedDelta, "live delta matches independent computation");
        assertEq(targetSize, expectedTarget, "target = h * delta");

        LambdaHook.PoolState memory ps = hook.poolState(key);
        assertEq(ps.hedgedDelta, expectedDelta, "hedgedDelta latched to live");
        assertEq(ps.hedgeNonce, 1, "nonce persisted");
    }

    function test_deposit_revertsIfNotConfigured() public {
        vm.expectRevert(LambdaHook.PoolNotConfigured.selector);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
    }

    function test_deposit_revertsOnZeroLiquidity() public {
        _configure(TAU);
        vm.expectRevert(LambdaHook.ZeroLiquidity.selector);
        hook.deposit(key, 0, type(uint256).max, type(uint256).max, address(this));
    }

    function test_deposit_revertsOnSlippage() public {
        _configure(TAU);
        vm.expectRevert(LambdaHook.Slippage.selector);
        hook.deposit(key, DEPOSIT_LIQ, 1, 1, address(this)); // max owed of 1 wei is unmeetable
    }

    function test_deposit_revertsWithoutApproval() public {
        _configure(TAU);
        // Revoke the token0 approval setUp granted: the vault can no longer pull the LP's funds,
        // so the settle's transferFrom fails and the whole deposit reverts (no funds half-moved).
        MockERC20(Currency.unwrap(currency0)).approve(address(hook), 0);
        vm.expectRevert(); // SafeTransferLib.TransferFromFailed inside _settle
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
    }

    function test_secondDeposit_sharesAreProRata() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
        (uint256 shares2,,) = hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        // liquidity doubled with equal add ⇒ second tranche mints the same share count.
        assertEq(shares2, DEPOSIT_LIQ, "equal add at unchanged price mints equal shares");
        assertEq(hook.poolState(key).liquidity, 2 * uint256(DEPOSIT_LIQ), "liquidity is additive");
        assertEq(hook.poolState(key).totalShares, 2 * uint256(DEPOSIT_LIQ), "shares are additive");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // swap → re-hedge signalling
    // ─────────────────────────────────────────────────────────────────────────

    function test_swap_triggersRehedgeWhenDriftExceedsTau() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
        assertEq(hook.poolState(key).hedgeNonce, 1, "deposit produced nonce 1");

        vm.recordLogs();
        // Sell token0 into the pool: price falls, the pool accumulates token0, delta rises.
        swap(key, true, -1e18, "");

        (bool found, uint64 nonce,, uint256 liveDelta) = _lastHedge();
        assertTrue(found, "swap past the band re-hedges");
        assertEq(nonce, 2, "second signal is nonce 2");

        LambdaHook.PoolState memory ps = hook.poolState(key);
        assertEq(ps.hedgeNonce, 2, "nonce advanced");
        assertEq(ps.hedgedDelta, liveDelta, "hedgedDelta re-latched to the new live delta");
        assertEq(ps.hedgedDelta, hook.currentDelta(key), "hedgedDelta equals the on-chain delta view");
        assertGt(liveDelta, 0, "delta is non-trivial");
    }

    function test_swap_withinBandDoesNotRehedge() public {
        // τ far larger than any plausible drift from a tiny swap.
        _configure(1e30);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
        // Wide band ⇒ even the initial deposit shouldn't signal.
        assertEq(hook.poolState(key).hedgeNonce, 0, "no signal under a wide band");

        vm.recordLogs();
        swap(key, true, -1e15, "");

        (bool found,,,) = _lastHedge();
        assertFalse(found, "small move inside the band raises no signal");
        assertEq(hook.poolState(key).hedgeNonce, 0, "nonce unchanged");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // withdraw
    // ─────────────────────────────────────────────────────────────────────────

    function test_withdraw_returnsTokensBurnsSharesAndClosesHedge() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        uint256 bal0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));
        uint256 bal1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));

        vm.recordLogs();
        (uint256 out0, uint256 out1) = hook.withdraw(key, DEPOSIT_LIQ, 0, 0, address(this));

        assertGt(out0, 0, "got token0 back");
        assertGt(out1, 0, "got token1 back");
        assertEq(MockERC20(Currency.unwrap(currency0)).balanceOf(address(this)) - bal0Before, out0, "token0 credited");
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(this)) - bal1Before, out1, "token1 credited");

        LambdaHook.PoolState memory ps = hook.poolState(key);
        assertEq(ps.liquidity, 0, "position fully removed");
        assertEq(ps.totalShares, 0, "all shares burned");
        assertEq(hook.sharesOf(key, address(this)), 0, "LP balance zeroed");

        // Closing the position drops delta to zero, which is itself a re-hedge (short → 0).
        (bool found,, uint256 targetSize, uint256 liveDelta) = _lastHedge();
        assertTrue(found, "emptying the vault signals a hedge close");
        assertEq(liveDelta, 0, "live delta is zero with no liquidity");
        assertEq(targetSize, 0, "target short is zero");
        assertEq(ps.hedgedDelta, 0, "hedge latched to zero");
    }

    function test_withdraw_revertsOnInsufficientShares() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
        vm.expectRevert(LambdaHook.InsufficientShares.selector);
        hook.withdraw(key, uint256(DEPOSIT_LIQ) + 1, 0, 0, address(this));
    }

    function test_withdraw_revertsOnSlippage() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
        vm.expectRevert(LambdaHook.Slippage.selector);
        hook.withdraw(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this)); // min out unmeetable
    }

    function test_partialWithdraw_leavesProRataPosition() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        hook.withdraw(key, uint256(DEPOSIT_LIQ) / 4, 0, 0, address(this));

        LambdaHook.PoolState memory ps = hook.poolState(key);
        assertApproxEqAbs(ps.liquidity, uint256(DEPOSIT_LIQ) * 3 / 4, 1, "three-quarters of liquidity remains");
        assertEq(ps.totalShares, uint256(DEPOSIT_LIQ) * 3 / 4, "three-quarters of shares remain");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // access control & invariants
    // ─────────────────────────────────────────────────────────────────────────

    function test_directLiquidity_isRejected() public {
        _configure(TAU);
        // The standard router tries to add liquidity directly; the hook forbids any LP but itself.
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER, tickUpper: TICK_UPPER, liquidityDelta: 1e18, salt: 0
            }),
            ""
        );
    }

    function test_configurePool_onlyOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hook.configurePool(key, TICK_LOWER, TICK_UPPER, TAU, 0);
    }

    function test_configurePool_rejectsDoubleConfigure() public {
        _configure(TAU);
        vm.expectRevert(LambdaHook.PoolAlreadyConfigured.selector);
        _configure(TAU);
    }

    function test_configurePool_rejectsUnalignedTicks() public {
        vm.expectRevert(LambdaHook.InvalidRange.selector);
        hook.configurePool(key, -601, 600, TAU, 0); // -601 not a multiple of tickSpacing
    }

    function test_configurePool_rejectsHedgeRatioAboveOne() public {
        vm.expectRevert(LambdaHook.InvalidHedgeRatio.selector);
        hook.configurePool(key, TICK_LOWER, TICK_UPPER, TAU, 1e18 + 1);
    }

    function test_setHedgeParams_updatesBandAndRatio() public {
        _configure(TAU);
        hook.setHedgeParams(key, 5e15, 0.5e18);
        LambdaHook.PoolState memory ps = hook.poolState(key);
        assertEq(ps.tau, 5e15, "tau updated");
        assertEq(ps.hedgeRatioWad, 0.5e18, "hedge ratio updated");
    }

    function test_unlockCallback_onlyPoolManager() public {
        vm.expectRevert(LambdaHook.NotPoolManager.selector);
        hook.unlockCallback("");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // directional fee (Nezlobin LVR defense)
    // ─────────────────────────────────────────────────────────────────────────

    function test_fee_seededAtBaseWhenPriceFlat() public {
        _configure(TAU);
        // Reference is seeded at the current tick ⇒ zero drift ⇒ base fee both ways.
        assertEq(hook.feeState(key).refTick, 0, "reference anchored at the 1:1 tick");
        assertEq(hook.previewFee(key, true), 3000, "flat price charges base");
        assertEq(hook.previewFee(key, false), 3000, "flat price charges base both directions");
    }

    function test_fee_requiresDynamicFeePool() public {
        // A static-fee pool on the same hook cannot be configured — the override would be inert.
        PoolKey memory sk = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // static
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        manager.initialize(sk, SQRT_PRICE_1_1);
        vm.expectRevert(LambdaHook.NotDynamicFee.selector);
        hook.configurePool(sk, TICK_LOWER, TICK_UPPER, TAU, 0);
    }

    function test_fee_isDirectionalAfterDrift() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        // Push price down with a sizable sell; the EMA reference lags, leaving residual drift.
        swap(key, true, -5e18, "");

        (, int24 tick,,) = manager.getSlot0(id);
        int24 refTick = hook.feeState(key).refTick;
        assertLt(tick, refTick, "price drifted below the lagging reference");

        uint24 feeContinue = hook.previewFee(key, true); // sell = continues the downward drift
        uint24 feeRevert = hook.previewFee(key, false); // buy = mean-reverting
        assertGt(feeContinue, 3000, "trend-continuing side is surcharged above base");
        assertLt(feeRevert, 3000, "mean-reverting side is discounted below base");
        assertGt(feeContinue, feeRevert, "informed flow pays strictly more");
    }

    function test_fee_referenceEmaTracksPrice() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        int24 refBefore = hook.feeState(key).refTick; // 0
        swap(key, true, -5e18, "");
        int24 refAfter = hook.feeState(key).refTick;
        (, int24 tick,,) = manager.getSlot0(id);

        // EMA nudges the reference toward the new (lower) tick, but not all the way.
        assertLt(refAfter, refBefore, "reference moved toward the new price");
        assertGt(refAfter, tick, "reference lags the live tick (partial EMA step)");
    }

    function test_setFeeParams_updatesAndValidates() public {
        _configure(TAU);
        hook.setFeeParams(key, 1000, 100, 5000, 25, 3000);
        LambdaHook.FeeState memory f = hook.feeState(key);
        assertEq(f.baseFeePips, 1000, "base updated");
        assertEq(f.minFeePips, 100, "min updated");
        assertEq(f.maxSurchargePips, 5000, "cap updated");
        assertEq(f.sensitivityPipsPerTick, 25, "sensitivity updated");
        assertEq(f.emaWeightBps, 3000, "ema weight updated");

        vm.expectRevert(LambdaHook.InvalidFeeParams.selector);
        hook.setFeeParams(key, 1000, 2000, 5000, 25, 3000); // min > base
        vm.expectRevert(LambdaHook.InvalidFeeParams.selector);
        hook.setFeeParams(key, 1000, 100, 5000, 25, 0); // ema weight 0
        vm.expectRevert(LambdaHook.InvalidFeeParams.selector);
        hook.setFeeParams(key, 1000, 100, 5000, 25, 10_001); // ema weight > 1
    }

    function test_setFeeParams_onlyOwner() public {
        _configure(TAU);
        vm.prank(address(0xBEEF));
        vm.expectRevert();
        hook.setFeeParams(key, 1000, 100, 5000, 25, 3000);
    }

    /// The override isn't cosmetic: the pool must actually charge it. With surcharge disabled
    /// (sensitivity 0) the fee is flat at `base`, so the only difference between the two runs
    /// is the fee level — a higher fee must leave the swapper with less output on identical state.
    function test_fee_isActuallyChargedOnSwap() public {
        _configure(TAU);
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        hook.setFeeParams(key, 100, 100, 0, 0, 2000); // flat 0.01%
        uint256 snap = vm.snapshotState();
        BalanceDelta dLow = swap(key, true, -1e18, "");
        int128 outLow = dLow.amount1(); // token1 received
        vm.revertToState(snap);

        hook.setFeeParams(key, 100_000, 100_000, 0, 0, 2000); // flat 10%
        BalanceDelta dHigh = swap(key, true, -1e18, "");
        int128 outHigh = dHigh.amount1();

        assertGt(outLow, outHigh, "higher override fee => less output => the pool charged it");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // log decoding
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Scan recorded logs for the most recent HedgeRequested and decode its fields.
    function _lastHedge() internal view returns (bool found, uint64 nonce, uint256 targetSize, uint256 liveDelta) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; i--) {
            Vm.Log memory log = logs[i - 1];
            if (log.topics.length == 3 && log.topics[0] == HEDGE_SIG && log.emitter == address(hook)) {
                nonce = uint64(uint256(log.topics[2]));
                (targetSize, liveDelta,,) = abi.decode(log.data, (uint256, uint256, uint160, uint256));
                return (true, nonce, targetSize, liveDelta);
            }
        }
        return (false, 0, 0, 0);
    }
}
