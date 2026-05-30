// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IYieldVenue
/// @notice Abstraction over the place idle insurance reserve earns yield. In production this
///         is an Aave V3 adapter (supply/withdraw the reserve asset); the interface lets
///         {InsuranceVault} stay venue-agnostic and fully testable against a mock.
/// @dev    The vault transfers `amount` of the asset to the venue *before* calling
///         {deposit}. {withdraw} sends the asset onward to `to`. {totalManaged} includes
///         accrued yield, so the vault's share price reflects earnings.
interface IYieldVenue {
    /// @notice The underlying reserve asset this venue manages.
    function asset() external view returns (address);

    /// @notice Put `amount` of the asset (already transferred in) to work.
    function deposit(uint256 amount) external;

    /// @notice Withdraw `amount` of the asset from the venue to `to`.
    function withdraw(uint256 amount, address to) external;

    /// @notice Total asset under management, including accrued yield.
    function totalManaged() external view returns (uint256);
}
