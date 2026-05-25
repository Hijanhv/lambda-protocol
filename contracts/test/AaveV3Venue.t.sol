// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {AaveV3Venue} from "../src/AaveV3Venue.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";
import {IAaveV3Pool} from "../src/interfaces/IAaveV3Pool.sol";

/// @notice Minimal Aave V3 Pool stand-in: supply pulls the underlying and mints aTokens 1:1;
///         withdraw burns aTokens and returns the underlying. Yield is simulated by minting
///         extra aTokens to a holder and matching underlying into the pool.
contract MockAavePool is IAaveV3Pool {
    using SafeTransferLib for address;

    MockERC20 public immutable underlying;
    MockERC20 public immutable aToken;

    constructor(MockERC20 _underlying, MockERC20 _aToken) {
        underlying = _underlying;
        aToken = _aToken;
    }

    function supply(address, uint256 amount, address onBehalfOf, uint16) external override {
        address(underlying).safeTransferFrom(msg.sender, address(this), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address, uint256 amount, address to) external override returns (uint256) {
        aToken.burn(msg.sender, amount);
        address(underlying).safeTransfer(to, amount);
        return amount;
    }
}

/// @notice Tests for {AaveV3Venue}: supply/withdraw plumbing, aToken-balance valuation
///         (yield), access control, and an end-to-end {InsuranceVault} reserve earning Aave
///         yield through the adapter.
contract AaveV3VenueTest is Test {
    MockERC20 internal usdc;
    MockERC20 internal aUsdc;
    MockAavePool internal pool;
    AaveV3Venue internal venue;

    address internal constant BOB = address(0xB0B);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aUsdc = new MockERC20("Aave USDC", "aUSDC", 6);
        pool = new MockAavePool(usdc, aUsdc);
        // vault = this test, so this drives deposit/withdraw directly.
        venue = new AaveV3Venue(address(usdc), address(aUsdc), IAaveV3Pool(address(pool)), address(this));
    }

    function _fund(uint256 amount) internal {
        usdc.mint(address(this), amount);
        usdc.transfer(address(venue), amount); // vault transfers in, then calls deposit
        venue.deposit(amount);
    }

    function test_depositSuppliesToPool() public {
        _fund(1000e6);
        assertEq(venue.totalManaged(), 1000e6, "managed == supplied");
        assertEq(aUsdc.balanceOf(address(venue)), 1000e6, "adapter holds aTokens");
        assertEq(usdc.balanceOf(address(pool)), 1000e6, "pool holds the underlying");
    }

    function test_withdrawReturnsUnderlying() public {
        _fund(1000e6);
        venue.withdraw(400e6, BOB);
        assertEq(usdc.balanceOf(BOB), 400e6, "underlying returned to recipient");
        assertEq(venue.totalManaged(), 600e6, "managed reduced");
    }

    function test_totalManagedReflectsYield() public {
        _fund(1000e6);
        // Simulate accrued interest: aToken rebases up, pool gains matching underlying.
        aUsdc.mint(address(venue), 50e6);
        usdc.mint(address(pool), 50e6);
        assertEq(venue.totalManaged(), 1050e6, "yield shows up in managed balance");
    }

    function test_onlyVaultCanDriveFunds() public {
        vm.startPrank(address(0xBAD));
        vm.expectRevert(AaveV3Venue.NotVault.selector);
        venue.deposit(1);
        vm.expectRevert(AaveV3Venue.NotVault.selector);
        venue.withdraw(1, BOB);
        vm.stopPrank();
    }

    function test_integration_insuranceVaultEarnsAaveYield() public {
        InsuranceVault vault = new InsuranceVault(address(usdc), address(this), address(this));
        AaveV3Venue adapter =
            new AaveV3Venue(address(usdc), address(aUsdc), IAaveV3Pool(address(pool)), address(vault));
        vault.setVenue(adapter);

        usdc.mint(address(this), 1000e6);
        usdc.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(1000e6, address(this));
        assertEq(adapter.totalManaged(), 1000e6, "reserve supplied to Aave");

        // Accrue yield on the Aave side.
        aUsdc.mint(address(adapter), 100e6);
        usdc.mint(address(pool), 100e6);
        assertEq(vault.totalAssets(), 1100e6, "reserve value includes Aave yield");

        uint256 got = vault.redeem(shares, address(this));
        assertEq(got, 1100e6, "backer redeems principal + Aave yield");
    }
}
