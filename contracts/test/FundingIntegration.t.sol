// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {LambdaHook} from "../src/LambdaHook.sol";
import {Funding} from "../src/Funding.sol";

/// @notice End-to-end test of the hook ⇋ Funding wiring: depositing/withdrawing through the
///         real {LambdaHook} mirrors share balances into {Funding} via the {IShareCallback},
///         and notified funding then splits to LPs pro-rata and pays out on claim. This is the
///         seam the unit tests stub out, exercised against a live PoolManager.
contract FundingIntegrationTest is Test, Deployers {
    LambdaHook internal hook;
    Funding internal funding;
    PoolId internal id;
    bytes32 internal pid;

    int24 internal constant TICK_LOWER = -600;
    int24 internal constant TICK_UPPER = 600;
    int24 internal constant TICK_SPACING = 60;
    uint128 internal constant DEPOSIT_LIQ = 1e21;
    uint256 internal constant TAU = 1e15;
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );
        address hookAddr = address(flags | (uint160(0x5555) << 144));
        deployCodeTo("LambdaHook.sol:LambdaHook", abi.encode(manager, address(this)), hookAddr);
        hook = LambdaHook(payable(hookAddr));

        (key, id) = initPool(currency0, currency1, IHooks(hookAddr), LPFeeLibrary.DYNAMIC_FEE_FLAG, TICK_SPACING, SQRT_PRICE_1_1);
        pid = PoolId.unwrap(id);
        hook.configurePool(key, TICK_LOWER, TICK_UPPER, TAU, 0);

        // Wire the funding ledger to the hook; pay funding in token1 (the USDC-like leg).
        funding = new Funding(address(this));
        hook.setShareCallback(address(funding));
        funding.setHook(address(hook));
        funding.setFunder(address(this), true);
        funding.registerPool(pid, Currency.unwrap(currency1));

        MockERC20(Currency.unwrap(currency0)).approve(hookAddr, type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(hookAddr, type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(address(funding), type(uint256).max);
    }

    function test_depositMirrorsSharesIntoFunding() public {
        (uint256 shares,,) = hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
        assertEq(shares, DEPOSIT_LIQ, "first deposit shares == liquidity");
        assertEq(funding.sharesOf(pid, address(this)), shares, "shares mirrored into Funding");
        assertEq(funding.poolInfo(pid).totalShares, shares, "totalShares mirrored");
    }

    function test_fundingFlowsToSoleLpAndPaysOnClaim() public {
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));

        uint256 amount = 1_000e18;
        funding.notifyFunding(pid, amount);
        assertEq(funding.pending(pid, address(this)), amount, "sole LP is owed all funding");

        uint256 balBefore = MockERC20(Currency.unwrap(currency1)).balanceOf(address(this));
        uint256 claimed = funding.claim(pid);
        assertEq(claimed, amount, "claims the full amount");
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(this)) - balBefore, amount, "funding paid out in token1");
    }

    function test_twoLpsSplitFundingProRata() public {
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this)); // this: L shares
        hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, BOB); // bob: equal shares

        funding.notifyFunding(pid, 1_000e18);
        assertEq(funding.pending(pid, address(this)), 500e18, "half to first LP");
        assertEq(funding.pending(pid, BOB), 500e18, "half to second LP");
    }

    function test_withdrawSettlesAndUpdatesMirror() public {
        (uint256 shares,,) = hook.deposit(key, DEPOSIT_LIQ, type(uint256).max, type(uint256).max, address(this));
        funding.notifyFunding(pid, 1_000e18); // owed before the withdraw

        hook.withdraw(key, shares / 2, 0, 0, address(this));

        // The withdraw settled the LP first, so the earned funding is preserved in full…
        assertEq(funding.pending(pid, address(this)), 1_000e18, "earned funding survives a withdraw");
        // …and the mirrored balance now reflects the reduced position.
        assertEq(funding.sharesOf(pid, address(this)), shares - shares / 2, "mirror halved");
        assertEq(funding.poolInfo(pid).totalShares, shares - shares / 2, "totalShares halved");
    }
}
