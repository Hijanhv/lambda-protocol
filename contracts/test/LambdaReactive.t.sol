// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LambdaReactive} from "../src/LambdaReactive.sol";
import {IReactive} from "reactive-lib/interfaces/IReactive.sol";

/// @notice Minimal stand-in for the Reactive system contract, recording subscriptions so we
///         can assert the network-side wiring. Etched at the well-known service address.
contract MockSystemContract {
    struct Sub {
        uint256 chainId;
        address contractAddr;
        uint256 t0;
        uint256 t1;
        uint256 t2;
        uint256 t3;
    }

    Sub[] public subs;

    function subscribe(uint256 c, address a, uint256 t0, uint256 t1, uint256 t2, uint256 t3) external {
        subs.push(Sub({chainId: c, contractAddr: a, t0: t0, t1: t1, t2: t2, t3: t3}));
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function subCount() external view returns (uint256) {
        return subs.length;
    }

    receive() external payable {}
}

/// @notice Tests for {LambdaReactive}. The contract runs in two environments; we exercise
///         both. In a bare Foundry VM (no system contract code) it behaves as the ReactVM
///         copy, so `react` is live and we drive it directly. With a mock system contract
///         etched at the service address it behaves as the network copy, so the constructor
///         subscribes — which we capture and assert.
contract LambdaReactiveTest is Test {
    address internal constant SERVICE = 0x0000000000000000000000000000000000fffFfF;

    uint256 internal constant ORIGIN_CHAIN = 130; // Unichain
    uint256 internal constant DEST_CHAIN = 999; // HyperEVM
    address internal constant HOOK = address(0x1111);
    address internal constant HEDGER = address(0x2222);
    uint256 internal constant CRON_TOPIC = uint256(keccak256("CRON")); // any nonzero topic
    uint64 internal constant GAS_LIMIT = 1_000_000;

    uint256 internal constant HEDGE_TOPIC0 =
        uint256(keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)"));

    bytes32 internal constant POOL = keccak256("ETH/USDC");

    LambdaReactive internal reactive;

    function setUp() public {
        // No code at SERVICE ⇒ detectVm() sets vm = true ⇒ ReactVM copy with a live react().
        reactive = new LambdaReactive(ORIGIN_CHAIN, HOOK, DEST_CHAIN, HEDGER, CRON_TOPIC, GAS_LIMIT);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // log builders
    // ─────────────────────────────────────────────────────────────────────────

    function _hedgeLog(bytes32 poolId, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
        internal
        view
        returns (IReactive.LogRecord memory l)
    {
        l.chain_id = ORIGIN_CHAIN;
        l._contract = HOOK;
        l.topic_0 = HEDGE_TOPIC0;
        l.topic_1 = uint256(poolId);
        l.topic_2 = nonce;
        l.data = abi.encode(
            targetSize,
            uint256(123e18),
            /*liveDelta*/
            sqrtPriceX96,
            block.timestamp
        );
    }

    /// @dev Find the most recent Reactive `Callback` and return its payload.
    function _lastCallback() internal view returns (bool found, bytes memory payload) {
        bytes32 sig = keccak256("Callback(uint256,address,uint64,bytes)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = logs.length; i > 0; i--) {
            if (logs[i - 1].topics[0] == sig && logs[i - 1].emitter == address(reactive)) {
                payload = abi.decode(logs[i - 1].data, (bytes));
                return (true, payload);
            }
        }
        return (false, "");
    }

    function _selector(bytes memory payload) internal pure returns (bytes4 s) {
        s = bytes4(payload[0]) | (bytes4(payload[1]) >> 8) | (bytes4(payload[2]) >> 16) | (bytes4(payload[3]) >> 24);
    }

    function _payloadArgs(bytes memory payload)
        internal
        pure
        returns (address rvm, bytes32 poolId, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
    {
        bytes memory body = new bytes(payload.length - 4);
        for (uint256 i = 0; i < body.length; i++) {
            body[i] = payload[i + 4];
        }
        (rvm, poolId, nonce, targetSize, sqrtPriceX96) = abi.decode(body, (address, bytes32, uint64, uint256, uint160));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // react() — hedge routing
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_routesHedgeCallback() public {
        vm.recordLogs();
        reactive.react(_hedgeLog(POOL, 1, 65e18, 79228162514264337593543950336));

        (bool found, bytes memory payload) = _lastCallback();
        assertTrue(found, "Callback emitted");

        // Targets applyHedge with a zero-address placeholder for the relayer to fill.
        assertEq(
            _selector(payload), bytes4(keccak256("applyHedge(address,bytes32,uint64,uint256,uint160)")), "selector"
        );
        (address rvm, bytes32 poolId, uint64 nonce, uint256 targetSize,) = _payloadArgs(payload);
        assertEq(rvm, address(0), "rvm placeholder");
        assertEq(poolId, POOL, "pool routed");
        assertEq(nonce, 1, "nonce forwarded");
        assertEq(targetSize, 65e18, "target forwarded");

        assertEq(reactive.lastNonce(POOL), 1, "nonce latched");
    }

    function test_react_dropsStaleNonce() public {
        reactive.react(_hedgeLog(POOL, 5, 65e18, 79228162514264337593543950336));

        vm.recordLogs();
        reactive.react(_hedgeLog(POOL, 5, 99e18, 79228162514264337593543950336)); // replay
        (bool found,) = _lastCallback();
        assertFalse(found, "replayed nonce raises no callback");
        assertEq(reactive.lastNonce(POOL), 5, "nonce unchanged");

        vm.recordLogs();
        reactive.react(_hedgeLog(POOL, 4, 99e18, 79228162514264337593543950336)); // older
        (found,) = _lastCallback();
        assertFalse(found, "older nonce raises no callback");
    }

    function test_react_ignoresForeignContractOrTopic() public {
        // Right topic, wrong emitter.
        IReactive.LogRecord memory wrongContract = _hedgeLog(POOL, 1, 65e18, 79228162514264337593543950336);
        wrongContract._contract = address(0xDEAD);

        vm.recordLogs();
        reactive.react(wrongContract);
        (bool found,) = _lastCallback();
        assertFalse(found, "events from other contracts are ignored");
        assertEq(reactive.lastNonce(POOL), 0, "nonce untouched");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // react() — cron routing
    // ─────────────────────────────────────────────────────────────────────────

    function test_react_routesCronToFundingCheckpoint() public {
        IReactive.LogRecord memory cron;
        cron.chain_id = block.chainid;
        cron._contract = SERVICE;
        cron.topic_0 = CRON_TOPIC;

        vm.recordLogs();
        reactive.react(cron);

        (bool found, bytes memory payload) = _lastCallback();
        assertTrue(found, "cron produces a callback");
        assertEq(_selector(payload), bytes4(keccak256("checkpointFunding(address)")), "funding selector");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // subscriptions (network-side copy)
    // ─────────────────────────────────────────────────────────────────────────

    function test_constructor_subscribesOnNetworkSide() public {
        // Etch the system contract so detectVm() sees code ⇒ vm = false ⇒ subscribe runs.
        vm.etch(SERVICE, address(new MockSystemContract()).code);
        LambdaReactive net = new LambdaReactive(ORIGIN_CHAIN, HOOK, DEST_CHAIN, HEDGER, CRON_TOPIC, GAS_LIMIT);
        assertTrue(address(net) != address(0));

        MockSystemContract sys = MockSystemContract(payable(SERVICE));
        assertEq(sys.subCount(), 2, "subscribes to hedge events and cron");

        (uint256 c, address a, uint256 t0,,,) = sys.subs(0);
        assertEq(c, ORIGIN_CHAIN, "hedge sub on origin chain");
        assertEq(a, HOOK, "hedge sub on the hook");
        assertEq(t0, HEDGE_TOPIC0, "hedge sub on the right topic");
    }

    function test_constructor_skipsCronSubWhenDisabled() public {
        vm.etch(SERVICE, address(new MockSystemContract()).code);
        new LambdaReactive(
            ORIGIN_CHAIN,
            HOOK,
            DEST_CHAIN,
            HEDGER,
            0,
            /* cron disabled */
            GAS_LIMIT
        );

        MockSystemContract sys = MockSystemContract(payable(SERVICE));
        assertEq(sys.subCount(), 1, "only the hedge subscription when cron is off");
    }
}
