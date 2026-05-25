// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Funding} from "../src/Funding.sol";

/// @notice Drives {Funding} through random share changes, funding deposits, and claims while
///         acting as both the hook (share reporter) and the funder.
contract FundingHandler is Test {
    Funding public funding;
    MockERC20 public token;
    bytes32 public pool;
    address[] public actors;

    uint256 public totalNotified;
    uint256 public totalClaimed;
    uint256 public shareChanges; // each can leave ≤1 wei of floor-rounding dust
    mapping(address => uint256) public mirrored;

    constructor(Funding _funding, MockERC20 _token, bytes32 _pool, address[] memory _actors) {
        funding = _funding;
        token = _token;
        pool = _pool;
        actors = _actors;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function changeShares(uint256 seed, uint256 newShares) external {
        address a = _actor(seed);
        newShares = bound(newShares, 0, 1e24);
        uint256 old = mirrored[a];
        funding.onSharesChanged(pool, a, old, newShares);
        mirrored[a] = newShares;
        shareChanges++;
    }

    function notify(uint256 amount) external {
        if (funding.poolInfo(pool).totalShares == 0) return;
        amount = bound(amount, 1, 1e18);
        token.mint(address(this), amount);
        token.approve(address(funding), amount);
        funding.notifyFunding(pool, amount);
        totalNotified += amount;
    }

    function claim(uint256 seed) external {
        address a = _actor(seed);
        vm.prank(a);
        totalClaimed += funding.claim(pool);
    }

    function sumMirrored() external view returns (uint256 s) {
        for (uint256 i; i < actors.length; ++i) {
            s += mirrored[actors[i]];
        }
    }

    function sumPending() external view returns (uint256 s) {
        for (uint256 i; i < actors.length; ++i) {
            s += funding.pending(pool, actors[i]);
        }
    }
}

/// @notice Invariants for {Funding}'s money path: the contract is always exactly solvent for
///         its outstanding funding liability, its mirrored total tracks the per-actor shares,
///         and no one can be owed more than was deposited and not yet paid.
contract FundingInvariantTest is Test {
    Funding internal funding;
    MockERC20 internal token;
    FundingHandler internal handler;
    bytes32 internal constant POOL = keccak256("ETH/USDC");

    function setUp() public {
        funding = new Funding(address(this));
        token = new MockERC20("USDC", "USDC", 6);

        address[] memory actors = new address[](4);
        actors[0] = address(0xA1);
        actors[1] = address(0xA2);
        actors[2] = address(0xA3);
        actors[3] = address(0xA4);

        handler = new FundingHandler(funding, token, POOL, actors);
        funding.setHook(address(handler));
        funding.setFunder(address(handler), true);
        funding.registerPool(POOL, address(token));

        targetContract(address(handler));
    }

    /// The contract holds exactly the funding it owes — no more, no less.
    function invariant_balanceEqualsUnclaimed() public view {
        assertEq(token.balanceOf(address(funding)), funding.poolInfo(POOL).unclaimed, "balance == unclaimed liability");
    }

    /// Unclaimed liability is exactly notified minus claimed.
    function invariant_unclaimedMatchesFlow() public view {
        assertEq(funding.poolInfo(POOL).unclaimed, handler.totalNotified() - handler.totalClaimed(), "unclaimed == notified - claimed");
    }

    /// The mirrored total equals the sum of per-actor share balances.
    function invariant_totalSharesMatchSum() public view {
        assertEq(funding.poolInfo(POOL).totalShares, handler.sumMirrored(), "totalShares == sum of shares");
    }

    /// Aggregate pending never exceeds the reserve beyond floor-rounding dust — bounded by the
    /// number of share changes (≤1 wei each). `claim` caps at `unclaimed`, so this dust can
    /// never make a payout revert; it only means a few wei roll into the next funding round.
    function invariant_pendingWithinReservePlusDust() public view {
        assertLe(handler.sumPending(), funding.poolInfo(POOL).unclaimed + handler.shareChanges(), "sum(pending) <= unclaimed + dust");
    }
}
