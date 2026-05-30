// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Funding} from "../src/Funding.sol";

/// @notice Unit tests for {Funding}'s rewards-per-share accounting. This contract plays the
///         role of the hook (the authorized share reporter) and of the funder, driving share
///         changes and funding deposits directly. The invariants that matter: funding splits
///         pro-rata to shares held, a late joiner earns nothing from funding that predates
///         them, and a balance change settles the holder before it takes effect.
contract FundingTest is Test {
    Funding internal funding;
    MockERC20 internal token;

    bytes32 internal constant POOL = keccak256("ETH/USDC");
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        funding = new Funding(address(this));
        token = new MockERC20("USD Coin", "USDC", 6);

        funding.setHook(address(this)); // this test acts as the hook
        funding.setFunder(address(this), true);
        funding.registerPool(POOL, address(token));

        token.mint(address(this), 1e24);
        token.approve(address(funding), type(uint256).max);
    }

    function _setShares(address who, uint256 oldS, uint256 newS) internal {
        funding.onSharesChanged(POOL, who, oldS, newS);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // distribution
    // ─────────────────────────────────────────────────────────────────────────

    function test_distributesProRataToShares() public {
        _setShares(ALICE, 0, 100e18);
        _setShares(BOB, 0, 300e18);

        funding.notifyFunding(POOL, 400e6);

        assertEq(funding.pending(POOL, ALICE), 100e6, "alice gets 1/4");
        assertEq(funding.pending(POOL, BOB), 300e6, "bob gets 3/4");

        vm.prank(ALICE);
        assertEq(funding.claim(POOL), 100e6, "alice claims her share");
        assertEq(token.balanceOf(ALICE), 100e6, "alice paid in token");
        assertEq(funding.pending(POOL, ALICE), 0, "nothing left after claim");
        assertEq(funding.pending(POOL, BOB), 300e6, "bob's accrual untouched by alice's claim");
    }

    function test_lateJoinerEarnsNothingFromPriorFunding() public {
        _setShares(ALICE, 0, 100e18);
        funding.notifyFunding(POOL, 100e6); // only alice present
        assertEq(funding.pending(POOL, ALICE), 100e6);

        _setShares(BOB, 0, 100e18); // bob joins after the first distribution
        assertEq(funding.pending(POOL, BOB), 0, "no claim on funding that predates joining");

        funding.notifyFunding(POOL, 200e6); // now split 50/50
        assertEq(funding.pending(POOL, ALICE), 100e6 + 100e6, "alice: prior + half of new");
        assertEq(funding.pending(POOL, BOB), 100e6, "bob: half of new only");
    }

    function test_balanceChangeSettlesBeforeItTakesEffect() public {
        _setShares(ALICE, 0, 100e18);
        funding.notifyFunding(POOL, 100e6); // alice owed 100

        // Alice fully exits. Her owed funding must be locked in before her balance drops.
        _setShares(ALICE, 100e18, 0);
        assertEq(funding.pending(POOL, ALICE), 100e6, "exit preserves earned funding");
        assertEq(funding.poolInfo(POOL).totalShares, 0, "totalShares mirror updated");

        vm.prank(ALICE);
        assertEq(funding.claim(POOL), 100e6, "alice still claims post-exit");
    }

    function test_topUpDoesNotRetroactivelyDilute() public {
        _setShares(ALICE, 0, 100e18);
        funding.notifyFunding(POOL, 100e6); // alice owed 100 on her 100 shares

        // Alice adds more; the settle-on-change means the earlier 100 is preserved, and the
        // larger balance only affects funding from here on.
        _setShares(ALICE, 100e18, 400e18);
        _setShares(BOB, 0, 100e18);
        funding.notifyFunding(POOL, 500e6); // total 500 shares: alice 4/5, bob 1/5

        assertEq(funding.pending(POOL, ALICE), 100e6 + 400e6, "prior 100 + 400 of the new 500");
        assertEq(funding.pending(POOL, BOB), 100e6, "1/5 of the new 500");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // access control & guards
    // ─────────────────────────────────────────────────────────────────────────

    function test_onSharesChanged_onlyHook() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(Funding.NotHook.selector);
        funding.onSharesChanged(POOL, ALICE, 0, 1e18);
    }

    function test_notifyFunding_onlyFunder() public {
        _setShares(ALICE, 0, 100e18);
        vm.prank(address(0xBAD));
        vm.expectRevert(Funding.NotFunder.selector);
        funding.notifyFunding(POOL, 1e6);
    }

    function test_notifyFunding_revertsWithNoShares() public {
        vm.expectRevert(Funding.NoShares.selector);
        funding.notifyFunding(POOL, 1e6);
    }

    function test_notifyFunding_revertsForUnregisteredPool() public {
        bytes32 other = keccak256("OTHER");
        vm.expectRevert(Funding.PoolNotRegistered.selector);
        funding.notifyFunding(other, 1e6);
    }

    function test_registerPool_guards() public {
        vm.expectRevert(Funding.PoolAlreadyRegistered.selector);
        funding.registerPool(POOL, address(token));

        vm.expectRevert(Funding.ZeroAddress.selector);
        funding.registerPool(keccak256("X"), address(0));

        vm.prank(address(0xBAD));
        vm.expectRevert(); // onlyOwner
        funding.registerPool(keccak256("Y"), address(token));
    }

    function test_claim_unregisteredReverts() public {
        vm.expectRevert(Funding.PoolNotRegistered.selector);
        funding.claim(keccak256("OTHER"));
    }

    function test_claim_withNothingPendingIsNoop() public {
        _setShares(ALICE, 0, 100e18);
        vm.prank(ALICE);
        assertEq(funding.claim(POOL), 0, "no funding, no payout");
        assertEq(token.balanceOf(ALICE), 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // solvency bookkeeping
    // ─────────────────────────────────────────────────────────────────────────

    function test_unclaimedTracksOutstandingLiability() public {
        _setShares(ALICE, 0, 100e18);
        _setShares(BOB, 0, 100e18);
        funding.notifyFunding(POOL, 200e6);
        assertEq(funding.poolInfo(POOL).unclaimed, 200e6, "all funding outstanding");

        vm.prank(ALICE);
        funding.claim(POOL);
        assertEq(funding.poolInfo(POOL).unclaimed, 100e6, "drops by what alice took");
        assertEq(token.balanceOf(address(funding)), 100e6, "contract still holds bob's share");
    }
}
