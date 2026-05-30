// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractReactive} from "reactive-lib/abstract-base/AbstractReactive.sol";

/// @title LambdaReactive
/// @notice The Reactive Network leg of Lambda (README §"How Lambda works ②"). A Reactive
///         Smart Contract that subscribes to the hook's `HedgeRequested` events on the origin
///         chain and, entirely on-chain with no off-chain bot, routes a callback to the
///         HyperEVM {LambdaHedger} that re-sizes the perp short. It can also subscribe to a
///         Reactive cron topic to drive periodic funding checkpoints.
///
/// @dev    Lifecycle, and why the same contract runs in two places:
///
///         • On the Reactive Network ("rnOnly") the constructor registers subscriptions with
///           the system contract. Each copy detects which side it is on via {detectVm}; only
///           the network-side copy subscribes.
///
///         • In the ReactVM ("vmOnly") {react} fires for every matched log. It is the
///           protocol's decision point: it enforces strictly increasing per-pool nonces
///           (dropping replays and out-of-order events) and emits a {Callback}. The Reactive
///           relayer turns that event into a transaction on the destination chain, filling in
///           the originating RVM id where we leave a zero-address placeholder.
///
///         The contract moves no funds and trusts no event payload for authorization — it
///         only forwards, and the hedger independently re-checks the nonce. Configuration is
///         immutable: the pair of chains, the two contract addresses, the topic filters, and
///         the callback gas budget are all fixed at deploy time.
contract LambdaReactive is AbstractReactive {
    // ─────────────────────────────────────────────────────────────────────────
    // Topics
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice topic_0 of LambdaHook.HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256).
    uint256 internal constant HEDGE_TOPIC0 =
        uint256(keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)"));

    // ─────────────────────────────────────────────────────────────────────────
    // Immutable configuration
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public immutable originChainId; // chain of the LambdaHook (e.g. Unichain)
    address public immutable hook; // LambdaHook address on the origin chain
    uint256 public immutable destinationChainId; // chain of the LambdaHedger (HyperEVM)
    address public immutable hedger; // LambdaHedger address on the destination chain
    uint256 public immutable cronTopic; // Reactive cron topic_0 to subscribe to; 0 disables
    uint64 public immutable callbackGasLimit; // gas budget passed to the relayer

    // ─────────────────────────────────────────────────────────────────────────
    // ReactVM state (per-pool dedupe)
    // ─────────────────────────────────────────────────────────────────────────

    mapping(bytes32 => uint64) public lastNonce;

    // ─────────────────────────────────────────────────────────────────────────
    // Events (RVM-side, for observability)
    // ─────────────────────────────────────────────────────────────────────────

    event HedgeRouted(bytes32 indexed poolId, uint64 indexed nonce, uint256 targetSize, uint160 sqrtPriceX96);
    event HedgeDropped(bytes32 indexed poolId, uint64 indexed nonce, uint64 lastApplied);
    event FundingTick(uint256 timestamp);

    // ─────────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        uint256 _originChainId,
        address _hook,
        uint256 _destinationChainId,
        address _hedger,
        uint256 _cronTopic,
        uint64 _callbackGasLimit
    ) {
        originChainId = _originChainId;
        hook = _hook;
        destinationChainId = _destinationChainId;
        hedger = _hedger;
        cronTopic = _cronTopic;
        callbackGasLimit = _callbackGasLimit;

        // Only the Reactive-Network copy subscribes; the ReactVM copy (vm == true) skips this.
        if (!vm) {
            service.subscribe(_originChainId, _hook, HEDGE_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
            if (_cronTopic != 0) {
                service.subscribe(
                    block.chainid, address(service), _cronTopic, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
                );
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reaction
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice ReactVM entry point: route a matched log to the hedge or funding path.
    function react(LogRecord calldata log) external vmOnly {
        if (log.topic_0 == HEDGE_TOPIC0 && log._contract == hook && log.chain_id == originChainId) {
            _routeHedge(log);
        } else if (cronTopic != 0 && log.topic_0 == cronTopic && log.chain_id == block.chainid) {
            _routeFunding();
        }
    }

    /// @dev Decode a HedgeRequested log, enforce nonce monotonicity, and emit the cross-chain
    ///      callback that re-sizes the short.
    function _routeHedge(LogRecord calldata log) internal {
        bytes32 poolId = bytes32(log.topic_1);
        uint64 nonce = uint64(log.topic_2);
        (uint256 targetSize,, uint160 sqrtPriceX96,) = abi.decode(log.data, (uint256, uint256, uint160, uint256));

        uint64 applied = lastNonce[poolId];
        if (nonce <= applied) {
            emit HedgeDropped(poolId, nonce, applied);
            return;
        }
        lastNonce[poolId] = nonce;

        // Leading zero address is the RVM-id placeholder the relayer fills in before the
        // destination call; the hedger re-validates the nonce, so the payload is not trusted.
        bytes memory payload = abi.encodeWithSignature(
            "applyHedge(address,bytes32,uint64,uint256,uint160)", address(0), poolId, nonce, targetSize, sqrtPriceX96
        );
        emit Callback(destinationChainId, hedger, callbackGasLimit, payload);
        emit HedgeRouted(poolId, nonce, targetSize, sqrtPriceX96);
    }

    /// @dev On a cron tick, ask the hedger to checkpoint funding.
    function _routeFunding() internal {
        bytes memory payload = abi.encodeWithSignature("checkpointFunding(address)", address(0));
        emit Callback(destinationChainId, hedger, callbackGasLimit, payload);
        emit FundingTick(block.timestamp);
    }
}
