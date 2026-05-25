// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractCallback} from "reactive-lib/abstract-base/AbstractCallback.sol";

/// @title LambdaHedgeReceiver
/// @notice Testnet-only destination receiver for the Reactive hedge callback.
///
/// @dev    Reactive Lasna cannot deliver callbacks to HyperEVM testnet (998) — HyperEVM is a
///         Reactive destination only on mainnet (999). So on testnet the hedge callback is
///         routed to Unichain Sepolia (`DESTINATION_CHAIN_ID=1301`) and lands here instead of
///         the real {LambdaHedger}, which can't run off HyperEVM because it calls the CoreWriter
///         precompile `0x3333…3333`.
///
///         This contract mirrors the hedger's two authorizations exactly — `authorizedSenderOnly`
///         (only the Reactive callback proxy may call) and strictly-increasing per-pool nonces
///         (replays/out-of-order dropped) — but RECORDS the requested hedge and emits an event
///         rather than sending a perp order. It proves the cross-chain automation half of the
///         loop end-to-end on testnet. On mainnet the real {LambdaHedger} takes this role with no
///         code change (just `DESTINATION_CHAIN_ID=999`). Not for production value flow.
contract LambdaHedgeReceiver is AbstractCallback {
    struct Hedge {
        uint64 lastNonce; // highest hook nonce applied
        uint64 count; // number of hedges received
        uint256 targetSize; // last requested short size, token0 WAD units
        uint160 sqrtPriceX96; // price reported with the request
    }

    mapping(bytes32 => Hedge) internal _hedges;

    /// @notice A hedge callback was received and recorded (no perp order — testnet stand-in).
    event HedgeReceived(bytes32 indexed poolId, uint64 indexed nonce, uint256 targetSize, uint160 sqrtPriceX96);
    /// @notice A cron-driven funding checkpoint callback was received.
    event FundingCheckpoint(address indexed rvmId, uint256 timestamp);

    error StaleNonce();

    /// @param callbackSender The Reactive callback proxy on the destination chain (Unichain
    ///        Sepolia: 0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4).
    constructor(address callbackSender) AbstractCallback(callbackSender) {}

    /// @notice Same signature and auth as {LambdaHedger.applyHedge}, minus the CoreWriter order.
    ///         Leading address is the RVM-id placeholder the relayer fills in; it is unused here.
    function applyHedge(address, bytes32 poolId, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
        external
        authorizedSenderOnly
    {
        Hedge storage h = _hedges[poolId];
        if (h.count != 0 && nonce <= h.lastNonce) revert StaleNonce();
        h.lastNonce = nonce;
        h.targetSize = targetSize;
        h.sqrtPriceX96 = sqrtPriceX96;
        unchecked {
            h.count += 1;
        }
        emit HedgeReceived(poolId, nonce, targetSize, sqrtPriceX96);
    }

    /// @notice Mirrors {LambdaHedger.checkpointFunding}.
    function checkpointFunding(address rvmId) external authorizedSenderOnly {
        emit FundingCheckpoint(rvmId, block.timestamp);
    }

    /// @notice Read the last recorded hedge for a pool.
    function hedge(bytes32 poolId) external view returns (Hedge memory) {
        return _hedges[poolId];
    }
}
