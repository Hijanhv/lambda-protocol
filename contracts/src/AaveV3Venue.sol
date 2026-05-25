// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {IYieldVenue} from "./interfaces/IYieldVenue.sol";
import {IAaveV3Pool} from "./interfaces/IAaveV3Pool.sol";

/// @title AaveV3Venue
/// @notice {IYieldVenue} adapter that parks {InsuranceVault}'s idle reserve in Aave V3 to earn
///         supply yield. The aToken rebases with interest, so `totalManaged` reads the aToken
///         balance directly — the vault's share price then reflects earnings automatically.
/// @dev    Only the owning vault may move funds. Supplied assets credit aTokens to this
///         adapter (`onBehalfOf = this`); withdrawals send the underlying onward to the
///         recipient the vault names.
contract AaveV3Venue is IYieldVenue {
    using SafeTransferLib for address;

    address public immutable override asset;
    address public immutable aToken; // Aave aToken for `asset` (1:1, rebasing)
    IAaveV3Pool public immutable pool;
    address public immutable vault; // the InsuranceVault allowed to drive this adapter

    error NotVault();

    constructor(address _asset, address _aToken, IAaveV3Pool _pool, address _vault) {
        asset = _asset;
        aToken = _aToken;
        pool = _pool;
        vault = _vault;
        // Approve the pool once to pull the underlying on supply.
        _asset.safeApprove(address(_pool), type(uint256).max);
    }

    modifier onlyVault() {
        _onlyVault();
        _;
    }

    function _onlyVault() internal view {
        if (msg.sender != vault) revert NotVault();
    }

    /// @inheritdoc IYieldVenue
    /// @dev The vault transfers the underlying here first, then calls this to supply it.
    function deposit(uint256 amount) external override onlyVault {
        pool.supply(asset, amount, address(this), 0);
    }

    /// @inheritdoc IYieldVenue
    function withdraw(uint256 amount, address to) external override onlyVault {
        pool.withdraw(asset, amount, to);
    }

    /// @inheritdoc IYieldVenue
    function totalManaged() external view override returns (uint256) {
        return IERC20Minimal(aToken).balanceOf(address(this));
    }
}
