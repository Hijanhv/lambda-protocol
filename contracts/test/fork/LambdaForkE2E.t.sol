// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

import {LambdaHook} from "../../src/LambdaHook.sol";
import {LambdaReactive} from "../../src/LambdaReactive.sol";
import {LambdaHedgeReceiver} from "../../src/LambdaHedgeReceiver.sol";
import {IReactive} from "reactive-lib/interfaces/IReactive.sol";

/// @title LambdaForkE2E
/// @notice Mainnet/testnet-fork integration test for Lambda's full cross-chain hedge loop,
///         run entirely on a local fork of Unichain Sepolia against the LIVE deployed
///         contracts (no redeploy, no testnet faucet, no gas spent).
///
/// @dev    WHAT THIS PROVES (against real on-chain state):
///         • leg ① — a real swap routed through the live PoolManager + live LambdaHook
///           moves the price and makes the live hook emit a real `HedgeRequested`.
///         • leg ② — that *real* event, fed into LambdaReactive's ReactVM entry point,
///           produces the cross-chain `Callback` targeting the live receiver.
///         • leg ③ — the callback, delivered while impersonating the real Reactive
///           callback proxy, is accepted by the live receiver (auth + monotonic nonce)
///           and recorded.
///
/// @dev    WHAT THIS DOES NOT PROVE (and is honestly out of scope for a fork):
///         • The Reactive Network's ReactVM/relayer actually observing the log and
///           delivering the callback in production — here we drive `react()` and the
///           proxy call ourselves. A fork copies one chain's state at one block; it does
///           not run the off-chain relayer that bridges the two chains.
///         • HyperLiquid's HyperCore execution — the real {LambdaHedger} talks to the
///           CoreWriter precompile `0x3333…3333`, whose effect is implemented by Hyper's
///           node, not by EVM bytecode a fork can copy. On testnet that leg is the
///           {LambdaHedgeReceiver} stand-in, which is what we exercise here.
///
/// @dev    RUN IT:
///           export UNICHAIN_SEPOLIA_RPC=https://...   # any Unichain Sepolia RPC
///           forge test --match-path 'contracts/test/fork/LambdaForkE2E.t.sol' -vvv
///         Optionally pin a block for determinism:
///           export UNICHAIN_SEPOLIA_FORK_BLOCK=<n>
///         With no RPC set, every test self-skips so the normal `forge test` stays green.
contract LambdaForkE2E is Test {
    using PoolIdLibrary for PoolKey;

    // ── Live deployment (Unichain Sepolia, chain 1301) ───────────────────────
    // Source: DEPLOY_TESTNET.md / frontend/.env.local. Update here if a redeploy moves them.
    address internal constant HOOK = 0x23C3da7CF53862Fd38640100D4FB764bE2d2cac0;
    address internal constant TWETH = 0x8f9D95aa23eb0D15FB1F17af3E5913296d519f79; // token0 (lower address)
    address internal constant TUSDC = 0xca3cB1b81a4332247B6ce62b89cd37d8Bc61767b; // token1
    address internal constant RECEIVER = 0x36C7AA315e4Cd8aB7E8CADfbD5B10A3Fb03c2E0C;
    // The Reactive callback proxy on Unichain Sepolia — the only authorized caller of the receiver.
    address internal constant CALLBACK_PROXY = 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4;

    bytes32 internal constant LIVE_POOL_ID = 0x92fcee81621f08f93eb2e42cbb5e42d969459a5e41cda459b329cbbd0ec4373b;

    uint24 internal constant DYNAMIC_FEE = 0x800000;
    int24 internal constant TICK_SPACING = 60;
    uint256 internal constant ORIGIN_CHAIN_ID = 1301; // hook chain (Unichain Sepolia)
    uint256 internal constant DEST_CHAIN_ID = 1301; // receiver chain (testnet: same chain)

    bytes32 internal constant HEDGE_SIG =
        keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)");

    bool internal _live; // true once a fork is selected; gates every test

    function setUp() public {
        string memory rpc = vm.envOr("UNICHAIN_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) return; // no RPC ⇒ tests self-skip
        uint256 pin = vm.envOr("UNICHAIN_SEPOLIA_FORK_BLOCK", uint256(0));
        if (pin == 0) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, pin);
        }
        _live = true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Topology: our reconstructed PoolKey must hash to the live poolId.
    //    If this fails, the token order / fee / tickSpacing constants are wrong.
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_poolTopologyMatchesLive() public {
        if (_skip()) return;
        PoolKey memory key = _liveKey();
        assertEq(PoolId.unwrap(key.toId()), LIVE_POOL_ID, "reconstructed PoolKey must equal the live poolId");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. The live hook is a real, configured, already-hedging vault.
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_liveHookIsConfiguredAndHedging() public {
        if (_skip()) return;
        LambdaHook hook = LambdaHook(payable(HOOK));
        PoolKey memory key = _liveKey();

        LambdaHook.PoolState memory ps = hook.poolState(key);
        assertTrue(ps.initialized, "live pool is configured");
        assertGt(ps.liquidity, 0, "vault holds seeded liquidity");
        assertGe(ps.hedgeNonce, 1, "the live hook has already signalled at least one hedge");

        assertGt(hook.currentDelta(key), 0, "live LP delta is nonzero");

        // Directional fee is live for both directions (override flag stripped by previewFee).
        assertGt(hook.previewFee(key, true), 0, "buy-side fee computed");
        assertGt(hook.previewFee(key, false), 0, "sell-side fee computed");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. The whole loop, end to end, against live contracts.
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_endToEndHedgeLoop() public {
        if (_skip()) return;
        LambdaHook hook = LambdaHook(payable(HOOK));
        IPoolManager pm = hook.poolManager();
        PoolKey memory key = _liveKey();

        // ── leg ① : route a real swap through the live pool, capture the real event ──
        PoolSwapTest router = new PoolSwapTest(pm);
        uint256 amtIn = 5e18; // 5 tWETH, exact input, zeroForOne
        deal(TWETH, address(this), amtIn);
        IERC20(TWETH).approve(address(router), amtIn);

        vm.recordLogs();
        router.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(amtIn),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        (bool emitted, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96) = _findHedgeRequested(HOOK);
        assertTrue(emitted, "live hook emitted HedgeRequested from the forked swap");
        assertGt(targetSize, 0, "non-trivial short target");

        // ── leg ② : feed the REAL event into the Reactive SC → cross-chain callback ──
        // On a fork there is no code at the service address, so this copy is the ReactVM
        // copy (vm == true) and react() is live — exactly as it runs inside the network.
        LambdaReactive reactive =
            new LambdaReactive(ORIGIN_CHAIN_ID, HOOK, DEST_CHAIN_ID, RECEIVER, 0, 1_000_000);

        vm.recordLogs();
        reactive.react(_hedgeLog(nonce, targetSize, sqrtPriceX96));
        (bool routed, bytes memory payload) = _lastCallback(address(reactive));
        assertTrue(routed, "reactive routed a cross-chain callback");

        (bytes32 poolId, uint64 cbNonce, uint256 cbSize, uint160 cbSqrt) = _decodeApplyHedge(payload);
        assertEq(poolId, LIVE_POOL_ID, "callback targets the live pool");
        assertEq(cbNonce, nonce, "callback forwards the hook nonce");

        // ── leg ③ : deliver the callback to the LIVE receiver as the real proxy would ──
        LambdaHedgeReceiver receiver = LambdaHedgeReceiver(payable(RECEIVER));
        uint64 liveNonce = receiver.hedge(LIVE_POOL_ID).lastNonce;
        // The receiver enforces strictly-increasing nonces against its accumulated live
        // state; ensure we exceed it (a real fresh relay naturally does).
        uint64 deliverNonce = cbNonce > liveNonce ? cbNonce : liveNonce + 1;

        vm.prank(CALLBACK_PROXY); // only the authorized callback proxy may call
        receiver.applyHedge(address(0), poolId, deliverNonce, cbSize, cbSqrt);

        LambdaHedgeReceiver.Hedge memory h = receiver.hedge(LIVE_POOL_ID);
        assertEq(h.lastNonce, deliverNonce, "live receiver recorded the cross-chain hedge");
        assertEq(h.targetSize, cbSize, "short size delivered intact across the loop");
    }

    // Negative control: an unauthorized address cannot deliver a hedge to the live receiver.
    function test_fork_receiverRejectsUnauthorizedCaller() public {
        if (_skip()) return;
        LambdaHedgeReceiver receiver = LambdaHedgeReceiver(payable(RECEIVER));
        uint64 next = receiver.hedge(LIVE_POOL_ID).lastNonce + 1;
        vm.prank(address(0xBADBAD));
        vm.expectRevert(); // "Authorized sender only"
        receiver.applyHedge(address(0), LIVE_POOL_ID, next, 1e18, uint160(1 << 96));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _skip() internal returns (bool) {
        if (!_live) {
            vm.skip(true);
            return true;
        }
        return false;
    }

    function _liveKey() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(TWETH),
            currency1: Currency.wrap(TUSDC),
            fee: DYNAMIC_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK)
        });
    }

    /// @dev Rebuild the ReactVM log record for a captured HedgeRequested, matching react()'s
    ///      filter (origin chain + hook + topic) and data layout.
    function _hedgeLog(uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
        internal
        view
        returns (IReactive.LogRecord memory l)
    {
        l.chain_id = ORIGIN_CHAIN_ID;
        l._contract = HOOK;
        l.topic_0 = uint256(HEDGE_SIG);
        l.topic_1 = uint256(LIVE_POOL_ID);
        l.topic_2 = nonce;
        // data = (targetSize, liveDelta, sqrtPriceX96, timestamp)
        l.data = abi.encode(targetSize, uint256(0), sqrtPriceX96, block.timestamp);
    }

    /// @dev Scan recorded logs for the most recent HedgeRequested emitted by `emitter`.
    function _findHedgeRequested(address emitter)
        internal
        returns (bool found, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; i--) {
            Vm.Log memory lg = logs[i - 1];
            if (lg.emitter == emitter && lg.topics.length >= 3 && lg.topics[0] == HEDGE_SIG) {
                nonce = uint64(uint256(lg.topics[2]));
                (targetSize,, sqrtPriceX96,) = abi.decode(lg.data, (uint256, uint256, uint160, uint256));
                return (true, nonce, targetSize, sqrtPriceX96);
            }
        }
    }

    /// @dev Most recent Reactive `Callback(uint256,address,uint64,bytes)` from `emitter`.
    function _lastCallback(address emitter) internal returns (bool found, bytes memory payload) {
        bytes32 sig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].emitter == emitter && logs[i - 1].topics[0] == sig) {
                payload = abi.decode(logs[i - 1].data, (bytes));
                return (true, payload);
            }
        }
    }

    /// @dev Decode an `applyHedge(address,bytes32,uint64,uint256,uint160)` calldata payload,
    ///      dropping the 4-byte selector (the leading address is the RVM-id placeholder).
    function _decodeApplyHedge(bytes memory payload)
        internal
        pure
        returns (bytes32 poolId, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
    {
        bytes memory body = new bytes(payload.length - 4);
        for (uint256 i = 0; i < body.length; i++) {
            body[i] = payload[i + 4];
        }
        (, poolId, nonce, targetSize, sqrtPriceX96) =
            abi.decode(body, (address, bytes32, uint64, uint256, uint160));
    }
}
