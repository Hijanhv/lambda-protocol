// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LambdaHedger} from "../../src/LambdaHedger.sol";
import {CoreWriterLib} from "../../src/libraries/CoreWriterLib.sol";
import {ICoreWriter, CORE_WRITER} from "../../src/interfaces/ICoreWriter.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @notice Records every raw action so the test can decode the order the hedger actually
///         fired at the precompile. Identical to the unit-test mock — see LambdaHedger.t.sol.
contract MockCoreWriter is ICoreWriter {
    bytes public lastAction;
    uint256 public calls;

    function sendRawAction(bytes calldata data) external {
        lastAction = data;
        calls++;
    }
}

/// @title LambdaHedgerForkHyperEVM
/// @notice Leg ② of Lambda's loop — the real Hyperliquid perp — exercised against a LIVE fork
///         of HyperEVM. The real {LambdaHedger} is deployed onto forked HyperEVM state, fed the
///         same callback {LambdaReactive} would deliver, and the exact CoreWriter order bytes it
///         fires are captured and asserted against the Hyperliquid action schema.
///
/// @dev    Together with `LambdaForkE2E.t.sol` (legs ① + ③ on a Unichain Sepolia fork), this
///         gives **all three legs exercised against their real chains' state** in one
///         `forge test` run.
///
/// @dev    WHY THE PRECOMPILE IS ETCHED-TO-CAPTURE (the honest boundary):
///         A fork copies HyperEVM's EVM state, but the CoreWriter precompile's *effect* —
///         placing the order on Hyperliquid's HyperCore order book — is implemented by Hyper's
///         node/validators, not by EVM bytecode a fork can copy. So a vanilla fork cannot
///         *execute* the order. We therefore `vm.etch` a recorder at `0x3333…3333` to capture
///         the exact action the hedger submits, and assert it matches the spec. Everything
///         else — the hedger contract, the size/price math, the order framing — runs against
///         real forked HyperEVM state. This proves leg ② builds a correct, real order; the
///         live HyperCore fill itself is proven only by an actual mainnet deployment.
///
/// @dev    RUN IT:
///           export HYPEREVM_RPC=https://rpc.hyperliquid.xyz/evm   # HyperEVM mainnet (chain 999)
///           forge test --match-path 'contracts/test/fork/LambdaHedgerForkHyperEVM.t.sol' -vvv
///         (a HyperEVM *testnet* RPC, chain 998, works too). With no RPC set the tests
///         self-skip, so the default `forge test` stays green and offline.
contract LambdaHedgerForkHyperEVM is Test {
    LambdaHedger internal hedger;

    bytes32 internal constant POOL = keccak256("ETH/USDC");
    uint32 internal constant ASSET = 1; // L1 perp asset index (e.g. ETH-PERP)
    uint16 internal constant SLIPPAGE_BPS = 50; // 0.5%
    uint160 internal sqrtP11; // price 1.0

    bool internal _live;

    function setUp() public {
        string memory rpc = vm.envOr("HYPEREVM_RPC", string(""));
        if (bytes(rpc).length == 0) return; // no RPC ⇒ tests self-skip
        uint256 pin = vm.envOr("HYPEREVM_FORK_BLOCK", uint256(0));
        if (pin == 0) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, pin);
        }
        _live = true;

        // Capture-only recorder at the canonical precompile address (see contract NatSpec).
        vm.etch(CORE_WRITER, address(new MockCoreWriter()).code);

        // callbackSender = this test ⇒ authorized to drive applyHedge; owner = this test.
        hedger = new LambdaHedger(address(this), address(this));
        // szScaleWad = 1 ⇒ sz(L1 lots) = sizeWad/1e18; pxScaleWad = 1e18 ⇒ px ≈ mid.
        hedger.configureMarket(POOL, ASSET, 1, 1e18, 0, SLIPPAGE_BPS, CoreWriterLib.TIF_IOC);

        sqrtP11 = TickMath.getSqrtPriceAtTick(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Sanity: we are genuinely on a HyperEVM fork.
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_isHyperEVM() public {
        if (_skip()) return;
        assertTrue(block.chainid == 999 || block.chainid == 998, "HYPEREVM_RPC must point at HyperEVM (998/999)");
        assertGt(block.number, 0, "forked at a real block");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // The real hedger opens a short and fires a correct CoreWriter order on HyperEVM state.
    // ─────────────────────────────────────────────────────────────────────────
    function test_fork_hedgerFiresRealCoreWriterShort() public {
        if (_skip()) return;

        // The callback {LambdaReactive} would deliver: open a short to h·delta for this pool.
        uint64 nonce = 1;
        uint256 targetSize = 100e18; // token0 WAD; e.g. 0.65 × delta from leg ①
        hedger.applyHedge(address(0), POOL, nonce, targetSize, sqrtP11);

        // Exactly one order hit the precompile.
        assertEq(MockCoreWriter(CORE_WRITER).calls(), 1, "one CoreWriter order submitted");

        bytes memory action = MockCoreWriter(CORE_WRITER).lastAction();

        // Action framing: 1 version byte (0x01) + 3-byte action id (limit order = 1).
        assertEq(uint8(action[0]), CoreWriterLib.ENCODING_VERSION, "encoding version 0x01");
        assertEq(uint8(action[1]), 0x00, "action id hi");
        assertEq(uint8(action[2]), 0x00, "action id mid");
        assertEq(uint8(action[3]), 0x01, "action id = limit order (1)");

        (uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 tif, uint128 cloid) =
            _lastOrder(action);

        assertEq(asset, ASSET, "correct L1 asset");
        assertFalse(isBuy, "opening a short means sell");
        assertFalse(reduceOnly, "growing the short is not reduce-only");
        assertEq(tif, CoreWriterLib.TIF_IOC, "taker time-in-force");
        assertGt(sz, 0, "non-zero size");
        assertGt(limitPx, 0, "priced");
        assertEq(cloid, _cloid(POOL, nonce), "deterministic client order id (pool, nonce)");

        // Hedger state advanced to the target.
        assertEq(hedger.shortSize(POOL), targetSize, "short recorded at target");
    }

    // A reduce (buy-back) is reduce-only, so a hedge close can never flip the position long.
    function test_fork_reduceIsReduceOnlyBuy() public {
        if (_skip()) return;
        hedger.applyHedge(address(0), POOL, 1, 100e18, sqrtP11); // open short 100
        hedger.applyHedge(address(0), POOL, 2, 40e18, sqrtP11); // shrink toward 40

        (, bool isBuy,,, bool reduceOnly,,) = _lastOrder(MockCoreWriter(CORE_WRITER).lastAction());
        assertTrue(isBuy, "shrinking the short buys back");
        assertTrue(reduceOnly, "buy-back is reduce-only");
        assertEq(hedger.shortSize(POOL), 40e18, "short reduced to target");
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

    /// @dev Strip the 4-byte (version + action-id) prefix and decode the order tuple.
    function _lastOrder(bytes memory action)
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

    /// @dev Mirror of LambdaHedger._cloid for the assertion.
    function _cloid(bytes32 poolId, uint64 nonce) internal pure returns (uint128) {
        return uint128(uint256(keccak256(abi.encodePacked(poolId, nonce))));
    }
}
