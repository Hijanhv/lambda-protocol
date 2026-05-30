// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IAaveV3Pool
/// @notice The two Aave V3 `Pool` entry points Lambda's reserve needs. The supplied asset is
///         credited as an aToken that rebases up with accrued interest, so the adapter reads
///         its aToken balance to value the position.
interface IAaveV3Pool {
    /// @notice Supply `amount` of `asset`, crediting aTokens to `onBehalfOf`.
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /// @notice Withdraw `amount` of `asset` to `to`; `type(uint256).max` withdraws all.
    /// @return The amount withdrawn.
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
