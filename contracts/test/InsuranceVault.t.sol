// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {InsuranceVault} from "../src/InsuranceVault.sol";
import {IYieldVenue} from "../src/interfaces/IYieldVenue.sol";

/// @notice A trivial yield venue that just custodies the asset; "yield" is simulated by
///         minting extra asset to it, which lifts {totalManaged} exactly like real interest.
contract MockYieldVenue is IYieldVenue {
    using SafeTransferLib for address;

    address public immutable override asset;

    constructor(address a) {
        asset = a;
    }

    function deposit(uint256) external override {} // asset is transferred in before the call
    function withdraw(uint256 amount, address to) external override {
        asset.safeTransfer(to, amount);
    }

    function totalManaged() external view override returns (uint256) {
        return MockERC20(asset).balanceOf(address(this));
    }
}

/// @notice Tests for {InsuranceVault}: ERC-4626-style share pricing, premium donations lifting
///         backers, coverage draws (capped, coverer-only) reducing the reserve, and the
///         optional yield venue (deposit routing, yield accrual, payout pull-through, migration).
contract InsuranceVaultTest is Test {
    InsuranceVault internal vault;
    MockERC20 internal usdc;

    address internal constant BACKER = address(0xBACE);
    address internal constant BOB = address(0xB0B);
    address internal constant HEDGER = address(0x4ED9E); // shortfall recipient

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        // coverer = this test (acts as the hedger/operator), owner = this test.
        vault = new InsuranceVault(address(usdc), address(this), address(this));

        usdc.mint(address(this), 1e24);
        usdc.mint(BACKER, 1e24);
        usdc.mint(BOB, 1e24);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(BACKER);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // share pricing (idle reserve, no venue)
    // ─────────────────────────────────────────────────────────────────────────

    function test_firstDepositMintsOneToOne() public {
        vm.prank(BACKER);
        uint256 shares = vault.deposit(1000e6, BACKER);
        assertEq(shares, 1000e6, "1:1 on first deposit");
        assertEq(vault.totalAssets(), 1000e6, "reserve holds the deposit");
        assertEq(vault.convertToAssets(shares), 1000e6, "shares value the deposit");
    }

    function test_redeemReturnsProRata() public {
        vm.prank(BACKER);
        uint256 shares = vault.deposit(1000e6, BACKER);
        vm.prank(BACKER);
        uint256 got = vault.redeem(shares / 2, BACKER);
        assertEq(got, 500e6, "half the shares -> half the reserve");
        assertEq(vault.totalAssets(), 500e6, "reserve halved");
    }

    function test_donationLiftsShareValue() public {
        vm.prank(BACKER);
        uint256 shares = vault.deposit(1000e6, BACKER);

        vault.donate(1000e6); // premium top-up, no new shares
        assertEq(vault.totalAssets(), 2000e6, "reserve doubled by the premium");
        assertEq(vault.convertToAssets(shares), 2000e6, "backer's shares now worth 2x");
    }

    function test_secondDepositPricedAtCurrentValue() public {
        vm.prank(BACKER);
        vault.deposit(1000e6, BACKER); // 1000 shares @ value 1000
        vault.donate(1000e6); // value now 2000 on 1000 shares -> price 2.0

        vm.prank(BOB);
        uint256 bobShares = vault.deposit(1000e6, BOB);
        assertEq(bobShares, 500e6, "bob pays the 2.0 price -> half the shares");
        assertEq(vault.convertToAssets(bobShares), 1000e6, "bob's stake still worth his deposit");
        assertEq(vault.convertToAssets(1000e6), 2000e6, "backer keeps the premium upside");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // coverage
    // ─────────────────────────────────────────────────────────────────────────

    function test_coverGapPaysAndShrinksReserve() public {
        vm.prank(BACKER);
        vault.deposit(1000e6, BACKER);

        uint256 paid = vault.coverGap(HEDGER, 400e6);
        assertEq(paid, 400e6, "full coverage paid");
        assertEq(usdc.balanceOf(HEDGER), 400e6, "hedger received the cover");
        assertEq(vault.totalAssets(), 600e6, "reserve reduced by the payout");
        assertEq(vault.totalCovered(), 400e6, "cumulative coverage tracked");
        assertEq(vault.convertToAssets(1000e6), 600e6, "backers absorb the loss");
    }

    function test_coverGapClampedToMaxPerEvent() public {
        vm.prank(BACKER);
        vault.deposit(1000e6, BACKER);
        vault.setMaxCoverPerEvent(100e6);

        uint256 paid = vault.coverGap(HEDGER, 400e6);
        assertEq(paid, 100e6, "clamped to the per-event cap");
        assertEq(usdc.balanceOf(HEDGER), 100e6);
    }

    function test_coverGapClampedToAvailableReserve() public {
        vm.prank(BACKER);
        vault.deposit(100e6, BACKER);

        uint256 paid = vault.coverGap(HEDGER, 500e6); // more than the reserve holds
        assertEq(paid, 100e6, "cannot pay more than the reserve");
        assertEq(vault.totalAssets(), 0, "reserve drained, not reverted");
    }

    function test_coverGap_onlyCoverer() public {
        vm.prank(BACKER);
        vault.deposit(1000e6, BACKER);
        vm.prank(address(0xBAD));
        vm.expectRevert(InsuranceVault.NotCoverer.selector);
        vault.coverGap(HEDGER, 100e6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // yield venue
    // ─────────────────────────────────────────────────────────────────────────

    function test_venueDepositRoutesAndYieldAccrues() public {
        MockYieldVenue venue = new MockYieldVenue(address(usdc));
        vault.setVenue(venue);

        vm.prank(BACKER);
        uint256 shares = vault.deposit(1000e6, BACKER);
        assertEq(usdc.balanceOf(address(vault)), 0, "idle swept to the venue");
        assertEq(venue.totalManaged(), 1000e6, "venue holds the reserve");

        usdc.mint(address(venue), 200e6); // simulate accrued yield
        assertEq(vault.totalAssets(), 1200e6, "yield counts toward reserve");

        vm.prank(BACKER);
        uint256 got = vault.redeem(shares, BACKER);
        assertEq(got, 1200e6, "backer redeems principal + yield");
    }

    function test_venueCoverPullsThrough() public {
        MockYieldVenue venue = new MockYieldVenue(address(usdc));
        vault.setVenue(venue);
        vm.prank(BACKER);
        vault.deposit(1000e6, BACKER);

        uint256 paid = vault.coverGap(HEDGER, 400e6);
        assertEq(paid, 400e6, "coverage pulled from the venue");
        assertEq(usdc.balanceOf(HEDGER), 400e6);
        assertEq(vault.totalAssets(), 600e6);
    }

    function test_setVenueMigratesBalance() public {
        vm.prank(BACKER);
        vault.deposit(1000e6, BACKER); // idle, no venue yet
        assertEq(usdc.balanceOf(address(vault)), 1000e6);

        MockYieldVenue venue = new MockYieldVenue(address(usdc));
        vault.setVenue(venue);
        assertEq(usdc.balanceOf(address(vault)), 0, "idle moved into the venue");
        assertEq(venue.totalManaged(), 1000e6);

        vault.setVenue(IYieldVenue(address(0))); // pull everything back to idle
        assertEq(usdc.balanceOf(address(vault)), 1000e6, "reserve back to idle");
        assertEq(vault.totalAssets(), 1000e6);
    }

    function test_setVenue_rejectsAssetMismatch() public {
        MockERC20 other = new MockERC20("DAI", "DAI", 18);
        MockYieldVenue wrong = new MockYieldVenue(address(other));
        vm.expectRevert(InsuranceVault.VenueAssetMismatch.selector);
        vault.setVenue(wrong);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // admin & guards
    // ─────────────────────────────────────────────────────────────────────────

    function test_admin_onlyOwner() public {
        vm.startPrank(address(0xBAD));
        vm.expectRevert();
        vault.setCoverer(address(0xBAD));
        vm.expectRevert();
        vault.setMaxCoverPerEvent(1);
        vm.expectRevert();
        vault.setVenue(IYieldVenue(address(0)));
        vm.stopPrank();
    }

    function test_deposit_guards() public {
        vm.expectRevert(InsuranceVault.ZeroAmount.selector);
        vault.deposit(0, BACKER);
        vm.expectRevert(InsuranceVault.ZeroAddress.selector);
        vault.deposit(1e6, address(0));
    }

    function test_redeem_insufficientShares() public {
        vm.prank(BACKER);
        uint256 shares = vault.deposit(1000e6, BACKER);
        vm.prank(BACKER);
        vm.expectRevert(InsuranceVault.InsufficientShares.selector);
        vault.redeem(shares + 1, BACKER);
    }
}
