// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {IShareCallback} from "./interfaces/IShareCallback.sol";

/// @title Funding
/// @notice Distributes the perp short's realized funding to LPs, pro-rata to their vault
///         shares and weighted by the time they held them — the income side of Lambda's
///         LVR ⇋ funding identity (README §4). This is where the structural loss comes back
///         to LPs as yield.
///
/// @dev    Standard rewards-per-share accumulator (the Synthetix/MasterChef pattern):
///
///           accFundingPerShare grows by amount/totalShares each time funding is notified;
///           an LP is owed  shares · accFundingPerShare − rewardDebt.
///
///         Correctness depends on settling an LP *before* their share balance moves, so
///         {LambdaHook} calls {onSharesChanged} on every deposit/withdraw. This contract
///         mirrors balances and `totalShares` from those callbacks — it is the single source
///         of truth for funding accounting, independent of the hook's internal ledger.
///
///         Funding physically arrives as an ERC-20 (e.g. USDC) via {notifyFunding}. On
///         Hyperliquid the short collects funding on L1; bridging that back to this chain is
///         an operational concern outside this contract — {notifyFunding} is the deposit
///         point a bridge or operator calls, and only addresses the owner authorizes can.
contract Funding is IShareCallback, Ownable {
    using SafeTransferLib for address;

    /// @dev Fixed-point scale for the per-share accumulator; wide enough that small funding
    ///      amounts over large share supplies don't truncate to zero.
    uint256 internal constant ACC_PRECISION = 1e30;

    struct Pool {
        bool registered;
        address token; // funding currency paid to LPs
        uint256 accFundingPerShare; // scaled by ACC_PRECISION
        uint256 totalShares; // mirror of the vault's outstanding shares
        uint256 unclaimed; // funding notified but not yet claimed (for accounting/solvency)
    }

    mapping(bytes32 => Pool) internal _pools;
    mapping(bytes32 => mapping(address => uint256)) internal _shares; // mirrored LP balances
    mapping(bytes32 => mapping(address => uint256)) internal _rewardDebt;
    mapping(bytes32 => mapping(address => uint256)) internal _accrued;

    /// @notice The LambdaHook authorized to report share changes.
    address public hook;

    /// @notice Addresses permitted to deposit funding (a bridge/relayer or operator).
    mapping(address => bool) public funders;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event HookSet(address indexed hook);
    event FunderSet(address indexed funder, bool allowed);
    event PoolRegistered(bytes32 indexed poolId, address indexed token);
    event FundingNotified(bytes32 indexed poolId, uint256 amount, uint256 accFundingPerShare);
    event Claimed(bytes32 indexed poolId, address indexed account, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error NotHook();
    error NotFunder();
    error PoolNotRegistered();
    error PoolAlreadyRegistered();
    error NoShares();
    error ZeroAddress();

    // ─────────────────────────────────────────────────────────────────────────
    // Construction / admin
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address owner_) {
        _initializeOwner(owner_);
    }

    function setHook(address _hook) external onlyOwner {
        hook = _hook;
        emit HookSet(_hook);
    }

    function setFunder(address funder, bool allowed) external onlyOwner {
        funders[funder] = allowed;
        emit FunderSet(funder, allowed);
    }

    /// @notice Register a pool and the ERC-20 its LPs are paid funding in. Share mirroring via
    ///         {onSharesChanged} works before registration; only payouts require it.
    function registerPool(bytes32 poolId, address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        Pool storage p = _pools[poolId];
        if (p.registered) revert PoolAlreadyRegistered();
        p.registered = true;
        p.token = token;
        emit PoolRegistered(poolId, token);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Share mirroring (hook callback)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IShareCallback
    /// @dev Settles the account at its *old* balance (so it keeps exactly the funding earned
    ///      while holding those shares), then adopts the new balance and resets its baseline.
    function onSharesChanged(bytes32 poolId, address account, uint256 oldShares, uint256 newShares) external {
        if (msg.sender != hook) revert NotHook();
        Pool storage p = _pools[poolId];

        _harvest(poolId, account); // accrue earnings on the current (old) balance

        _shares[poolId][account] = newShares;
        p.totalShares = p.totalShares - oldShares + newShares;
        _rewardDebt[poolId][account] = FixedPointMathLib.fullMulDiv(newShares, p.accFundingPerShare, ACC_PRECISION);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Funding distribution & claims
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deposit `amount` of the pool's funding token and distribute it across current
    ///         shareholders. Pulls the tokens from the caller (an authorized funder).
    function notifyFunding(bytes32 poolId, uint256 amount) external {
        if (!funders[msg.sender]) revert NotFunder();
        Pool storage p = _pools[poolId];
        if (!p.registered) revert PoolNotRegistered();
        if (p.totalShares == 0) revert NoShares();

        p.token.safeTransferFrom(msg.sender, address(this), amount);
        p.accFundingPerShare += FixedPointMathLib.fullMulDiv(amount, ACC_PRECISION, p.totalShares);
        p.unclaimed += amount;
        emit FundingNotified(poolId, amount, p.accFundingPerShare);
    }

    /// @notice Claim all funding accrued to the caller for a pool.
    function claim(bytes32 poolId) external returns (uint256 amount) {
        Pool storage p = _pools[poolId];
        if (!p.registered) revert PoolNotRegistered();

        _harvest(poolId, msg.sender);
        amount = _accrued[poolId][msg.sender];
        // Floor-rounding in the per-share accumulator can, over many share changes, leave the
        // summed accruals a few wei above the funding actually deposited. Cap the payout at the
        // pool's outstanding liability so the last claimant can never be left short (the held
        // balance always covers `unclaimed`); any sub-wei residual rolls into the next round.
        uint256 cap = p.unclaimed;
        if (amount > cap) amount = cap;
        if (amount > 0) {
            _accrued[poolId][msg.sender] -= amount;
            p.unclaimed -= amount;
            p.token.safeTransfer(msg.sender, amount);
            emit Claimed(poolId, msg.sender, amount);
        }
    }

    /// @dev Move newly-earned funding (at the current balance and accumulator) into `accrued`
    ///      and advance the account's baseline. Idempotent within a block.
    function _harvest(bytes32 poolId, address account) internal {
        Pool storage p = _pools[poolId];
        uint256 entitled = FixedPointMathLib.fullMulDiv(_shares[poolId][account], p.accFundingPerShare, ACC_PRECISION);
        uint256 debt = _rewardDebt[poolId][account];
        if (entitled > debt) _accrued[poolId][account] += entitled - debt;
        _rewardDebt[poolId][account] = entitled;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Funding currently claimable by `account` in `poolId` (accrued + unsettled).
    function pending(bytes32 poolId, address account) external view returns (uint256) {
        Pool storage p = _pools[poolId];
        uint256 entitled = FixedPointMathLib.fullMulDiv(_shares[poolId][account], p.accFundingPerShare, ACC_PRECISION);
        uint256 debt = _rewardDebt[poolId][account];
        uint256 extra = entitled > debt ? entitled - debt : 0;
        return _accrued[poolId][account] + extra;
    }

    function poolInfo(bytes32 poolId) external view returns (Pool memory) {
        return _pools[poolId];
    }

    function sharesOf(bytes32 poolId, address account) external view returns (uint256) {
        return _shares[poolId][account];
    }
}
