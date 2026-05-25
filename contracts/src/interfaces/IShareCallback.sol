// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IShareCallback
/// @notice Hook → ledger notification fired whenever an LP's vault share balance changes.
/// @dev    Funding accrual uses a rewards-per-share accumulator, which is only correct if a
///         holder's position is settled at the exact moment their balance changes (the
///         Synthetix `updateReward` pattern). {LambdaHook} calls this on every deposit and
///         withdraw so {Funding} can mirror balances and settle before they move.
interface IShareCallback {
    /// @param poolId    The pool whose vault shares changed (PoolId as bytes32).
    /// @param account   The LP whose balance changed.
    /// @param oldShares The account's share balance before the change.
    /// @param newShares The account's share balance after the change.
    function onSharesChanged(bytes32 poolId, address account, uint256 oldShares, uint256 newShares) external;
}
