// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {IYieldVenue} from "./interfaces/IYieldVenue.sol";

/// @title InsuranceVault
/// @notice The reserve that backstops Lambda's hedge (README §Security). A perp short can be
///         liquidated in a violent move; if closing or topping it up leaves a shortfall, the
///         hedger draws from this reserve to keep LPs whole. Between such events the reserve
///         earns yield (Aave V3 in production, via an {IYieldVenue} adapter) and absorbs
///         protocol premiums, so backers are paid to stand behind the tail risk.
///
/// @dev    Share accounting is ERC-4626-style without the token wrapper: a backer's shares
///         claim a pro-rata slice of {totalAssets} (idle balance + whatever the yield venue
///         manages, including accrued yield). Three asset flows move the share price:
///
///           • deposit/redeem — backers in and out at the current price (price-neutral).
///           • donate         — premiums added with no shares minted (price ↑ for backers).
///           • coverGap       — the hedger draws to cover a shortfall (price ↓; backers
///                              absorb the loss, which is the whole point of insurance).
///
///         `coverGap` is the only privileged outflow: callable solely by the `coverer`
///         (the hedger/operator), bounded by `maxCoverPerEvent` and by available reserve.
///         The venue is swappable; switching it moves the managed balance across.
contract InsuranceVault is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;

    // ─────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The reserve asset (e.g. USDC).
    address public immutable asset;

    /// @notice Address allowed to draw coverage — the hedger or protocol operator.
    address public coverer;

    /// @notice Optional yield venue for idle reserve; zero keeps funds idle in this contract.
    IYieldVenue public venue;

    /// @notice Per-event coverage cap; 0 means uncapped (bounded only by available reserve).
    uint256 public maxCoverPerEvent;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    /// @notice Cumulative reserve paid out to cover gaps.
    uint256 public totalCovered;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    event CovererSet(address indexed coverer);
    event VenueSet(address indexed venue);
    event MaxCoverPerEventSet(uint256 maxCoverPerEvent);
    event Deposited(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event Redeemed(address indexed caller, address indexed receiver, uint256 shares, uint256 assets);
    event Donated(address indexed from, uint256 assets);
    event GapCovered(address indexed to, uint256 requested, uint256 paid);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error NotCoverer();
    error ZeroAmount();
    error ZeroAddress();
    error ZeroShares();
    error InsufficientShares();
    error VenueAssetMismatch();

    // ─────────────────────────────────────────────────────────────────────────
    // Construction / admin
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address _asset, address _coverer, address owner_) {
        if (_asset == address(0)) revert ZeroAddress();
        asset = _asset;
        coverer = _coverer;
        _initializeOwner(owner_);
        emit CovererSet(_coverer);
    }

    modifier onlyCoverer() {
        _onlyCoverer();
        _;
    }

    function _onlyCoverer() internal view {
        if (msg.sender != coverer) revert NotCoverer();
    }

    function setCoverer(address _coverer) external onlyOwner {
        coverer = _coverer;
        emit CovererSet(_coverer);
    }

    function setMaxCoverPerEvent(uint256 cap) external onlyOwner {
        maxCoverPerEvent = cap;
        emit MaxCoverPerEventSet(cap);
    }

    /// @notice Set or replace the yield venue, moving the whole managed balance across so the
    ///         reserve keeps earning. Pass the zero address to pull everything back to idle.
    function setVenue(IYieldVenue newVenue) external onlyOwner nonReentrant {
        if (address(newVenue) != address(0) && newVenue.asset() != asset) revert VenueAssetMismatch();

        IYieldVenue old = venue;
        if (address(old) != address(0)) {
            uint256 managed = old.totalManaged();
            if (managed > 0) old.withdraw(managed, address(this)); // back to idle first
        }
        venue = newVenue;
        if (address(newVenue) != address(0)) {
            uint256 idle = _idle();
            if (idle > 0) {
                asset.safeTransfer(address(newVenue), idle);
                newVenue.deposit(idle);
            }
        }
        emit VenueSet(address(newVenue));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Backer entry / exit
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deposit `assets` of reserve and mint shares to `receiver`.
    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        uint256 ta = totalAssets(); // snapshot before the inflow
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // First deposit anchors 1:1; later deposits price against the live reserve value.
        shares = totalShares == 0 ? assets : FixedPointMathLib.fullMulDiv(assets, totalShares, ta);
        // Never mint 0 shares for real assets — defeats the ERC-4626 first-depositor/donation
        // share-inflation grief (a victim reverts instead of depositing for nothing).
        if (shares == 0) revert ZeroShares();

        _deployToVenue(assets);
        totalShares += shares;
        sharesOf[receiver] += shares;
        emit Deposited(msg.sender, receiver, assets, shares);
    }

    /// @notice Burn `shares` and send the proportional reserve to `receiver`.
    function redeem(uint256 shares, address receiver) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        uint256 bal = sharesOf[msg.sender];
        if (shares > bal) revert InsufficientShares();

        assets = FixedPointMathLib.fullMulDiv(shares, totalAssets(), totalShares);
        sharesOf[msg.sender] = bal - shares;
        totalShares -= shares;
        _payout(receiver, assets);
        emit Redeemed(msg.sender, receiver, shares, assets);
    }

    /// @notice Add `assets` to the reserve without minting shares — premiums/top-ups that lift
    ///         every backer's share value. Callable by anyone (e.g. a fee router).
    function donate(uint256 assets) external nonReentrant {
        if (assets == 0) revert ZeroAmount();
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _deployToVenue(assets);
        emit Donated(msg.sender, assets);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Coverage
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Draw up to `amount` of reserve to cover a hedge shortfall, paying `to`.
    /// @dev    Only the coverer. Clamped to {maxCoverPerEvent} (if set) and to the available
    ///         reserve, so it degrades gracefully rather than reverting when under-funded.
    /// @return paid The amount actually paid out.
    function coverGap(address to, uint256 amount) external onlyCoverer nonReentrant returns (uint256 paid) {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        paid = amount;
        if (maxCoverPerEvent != 0 && paid > maxCoverPerEvent) paid = maxCoverPerEvent;
        uint256 avail = totalAssets();
        if (paid > avail) paid = avail;

        if (paid > 0) {
            totalCovered += paid;
            _payout(to, paid);
        }
        emit GapCovered(to, amount, paid);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internals
    // ─────────────────────────────────────────────────────────────────────────

    function _idle() internal view returns (uint256) {
        return IERC20Minimal(asset).balanceOf(address(this));
    }

    /// @dev Route freshly received assets to the venue (if any) to start earning.
    function _deployToVenue(uint256 amount) internal {
        IYieldVenue v = venue;
        if (address(v) != address(0) && amount > 0) {
            asset.safeTransfer(address(v), amount);
            v.deposit(amount);
        }
    }

    /// @dev Pay `amount` to `to`, pulling from the venue first if idle funds fall short.
    function _payout(address to, uint256 amount) internal {
        if (amount == 0) return;
        uint256 idle = _idle();
        if (idle < amount) {
            IYieldVenue v = venue;
            if (address(v) != address(0)) v.withdraw(amount - idle, address(this));
        }
        asset.safeTransfer(to, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Total reserve backing shares: idle balance plus venue-managed (incl. yield).
    function totalAssets() public view returns (uint256) {
        IYieldVenue v = venue;
        return _idle() + (address(v) == address(0) ? 0 : v.totalManaged());
    }

    /// @notice Reserve value of `shares` at the current price.
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return totalShares == 0 ? shares : FixedPointMathLib.fullMulDiv(shares, totalAssets(), totalShares);
    }

    /// @notice Shares minted for depositing `assets` at the current price.
    function convertToShares(uint256 assets) external view returns (uint256) {
        uint256 ta = totalAssets();
        return (totalShares == 0 || ta == 0) ? assets : FixedPointMathLib.fullMulDiv(assets, totalShares, ta);
    }
}
