// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

import {LambdaConfig} from "./LambdaConfig.sol";
import {LambdaHook} from "../src/LambdaHook.sol";

interface IERC20Min {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/// @notice One-command demo seeding (testnet/demo only). Deposits liquidity into the Lambda pool
///         — which fires the first `HedgeRequested` — then does a small swap to move the price so
///         a second, drift-triggered `HedgeRequested` fires. After this the dashboard reads live
///         data and the deposit quoter works. Uses the tokens the broadcaster already holds
///         (mint them first with `DeployTestTokens`).
/// @dev    Env: HOOK, POOL_MANAGER, TOKEN0, TOKEN1 (+ optional TICK_SPACING, SEED_LIQ, SWAP_AMOUNT).
///         `forge script contracts/script/SeedDemo.s.sol --rpc-url $UNICHAIN_RPC --private-key $PRIVATE_KEY --broadcast`
contract SeedDemo is LambdaConfig {
    using PoolIdLibrary for PoolKey;

    function run() external {
        address hookAddr = hookAddress();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 seedLiq = uint128(vm.envOr("SEED_LIQ", uint256(1e21)));
        uint256 swapAmt = vm.envOr("SWAP_AMOUNT", uint256(1e18));

        (Currency c0, Currency c1) = _sorted(token0(), token1());
        PoolKey memory key =
            PoolKey({currency0: c0, currency1: c1, fee: DYNAMIC_FEE, tickSpacing: tickSpacing(), hooks: IHooks(hookAddr)});
        address a0 = Currency.unwrap(c0);
        address a1 = Currency.unwrap(c1);

        vm.startBroadcast();

        // Deposit → mints shares and fires the first HedgeRequested.
        IERC20Min(a0).approve(hookAddr, type(uint256).max);
        IERC20Min(a1).approve(hookAddr, type(uint256).max);
        (uint256 shares,,) =
            LambdaHook(payable(hookAddr)).deposit(key, seedLiq, type(uint256).max, type(uint256).max, msg.sender);

        // Swap to move the price → delta drifts past τ → a second HedgeRequested (nonce bump).
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(poolManager()));
        IERC20Min(a0).approve(address(swapRouter), type(uint256).max);
        IERC20Min(a1).approve(address(swapRouter), type(uint256).max);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: true,
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(swapAmt), // exact input
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        vm.stopBroadcast();

        LambdaHook.PoolState memory ps = LambdaHook(payable(hookAddr)).poolState(key);
        console2.log("seeded shares  ", shares);
        console2.log("pool liquidity ", ps.liquidity);
        console2.log("hedge nonce    ", uint256(ps.hedgeNonce));
        console2.log("poolId         ", vm.toString(PoolId.unwrap(key.toId())));
    }

    function _sorted(address a, address b) internal pure returns (Currency, Currency) {
        return a < b ? (Currency.wrap(a), Currency.wrap(b)) : (Currency.wrap(b), Currency.wrap(a));
    }
}
