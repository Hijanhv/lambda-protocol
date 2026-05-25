// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";

/// @notice Drives {InsuranceVault} (idle reserve, no venue) through deposits, redeems,
///         premium donations, and coverage draws. The handler is the coverer.
contract VaultHandler is Test {
    InsuranceVault public vault;
    MockERC20 public token;
    address[] public actors;

    constructor(InsuranceVault _vault, MockERC20 _token, address[] memory _actors) {
        vault = _vault;
        token = _token;
        actors = _actors;
        for (uint256 i; i < actors.length; ++i) {
            token.mint(actors[i], 1e30);
            vm.prank(actors[i]);
            token.approve(address(vault), type(uint256).max);
        }
        token.mint(address(this), 1e30);
        token.approve(address(vault), type(uint256).max);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 seed, uint256 assets) external {
        address a = _actor(seed);
        assets = bound(assets, 1, 1e24);
        vm.prank(a);
        vault.deposit(assets, a);
    }

    function redeem(uint256 seed, uint256 shares) external {
        address a = _actor(seed);
        uint256 bal = vault.sharesOf(a);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(a);
        vault.redeem(shares, a);
    }

    function donate(uint256 assets) external {
        assets = bound(assets, 1, 1e22);
        vault.donate(assets);
    }

    function cover(uint256 amount) external {
        amount = bound(amount, 1, 1e24);
        vault.coverGap(address(this), amount); // handler is the coverer
    }

    function sumShares() external view returns (uint256 s) {
        for (uint256 i; i < actors.length; ++i) {
            s += vault.sharesOf(actors[i]);
        }
    }

    function sumRedeemable() external view returns (uint256 s) {
        for (uint256 i; i < actors.length; ++i) {
            s += vault.convertToAssets(vault.sharesOf(actors[i]));
        }
    }
}

/// @notice Invariants for {InsuranceVault}'s money path (idle mode): shares always sum to the
///         total, the held reserve always equals the accounted reserve, and backers can never
///         redeem more in aggregate than the reserve holds.
contract InsuranceVaultInvariantTest is Test {
    InsuranceVault internal vault;
    MockERC20 internal token;
    VaultHandler internal handler;

    function setUp() public {
        token = new MockERC20("USDC", "USDC", 6);
        // Deploy with a placeholder coverer, then point it at the handler.
        vault = new InsuranceVault(address(token), address(this), address(this));

        address[] memory actors = new address[](4);
        actors[0] = address(0xB1);
        actors[1] = address(0xB2);
        actors[2] = address(0xB3);
        actors[3] = address(0xB4);

        handler = new VaultHandler(vault, token, actors);
        vault.setCoverer(address(handler));

        targetContract(address(handler));
    }

    /// Per-actor shares always sum to the recorded total.
    function invariant_sharesSumToTotal() public view {
        assertEq(handler.sumShares(), vault.totalShares(), "sum(shares) == totalShares");
    }

    /// Idle reserve: the tokens held equal the accounted reserve exactly.
    function invariant_heldEqualsAccounted() public view {
        assertEq(token.balanceOf(address(vault)), vault.totalAssets(), "held == totalAssets (idle)");
    }

    /// Backers can never, in aggregate, redeem more than the reserve holds.
    function invariant_redeemableWithinReserve() public view {
        assertLe(handler.sumRedeemable(), vault.totalAssets() + 1, "sum(redeemable) <= reserve (+dust)");
    }
}
