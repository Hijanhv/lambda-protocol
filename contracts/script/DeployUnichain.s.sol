// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {LambdaConfig} from "./LambdaConfig.sol";
import {HookMiner} from "./HookMiner.sol";
import {LambdaHook} from "../src/LambdaHook.sol";
import {Funding} from "../src/Funding.sol";
import {InsuranceVault} from "../src/InsuranceVault.sol";

/// @notice Deploys the Unichain leg: the {LambdaHook} (at a CREATE2-mined permission address),
///         {Funding}, and optionally {InsuranceVault}; initializes the dynamic-fee pool;
///         configures the managed range; and wires the funding ledger to the hook.
/// @dev    Broadcaster must equal the intended owner (the wiring calls are owner-gated).
///         Run: `forge script contracts/script/DeployUnichain.s.sol --rpc-url $UNICHAIN_RPC --broadcast`.
contract DeployUnichain is LambdaConfig {
    using PoolIdLibrary for PoolKey;

    function run() external {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );
        bytes memory args = abi.encode(IPoolManager(poolManager()), owner());
        (address mined, bytes32 salt) = HookMiner.find(CREATE2_DEPLOYER, flags, type(LambdaHook).creationCode, args);

        vm.startBroadcast();

        LambdaHook hook = new LambdaHook{salt: salt}(IPoolManager(poolManager()), owner());
        require(address(hook) == mined, "hook address mismatch");

        Funding funding = new Funding(owner());
        hook.setShareCallback(address(funding));
        funding.setHook(address(hook));

        // Sort currencies and initialize the dynamic-fee pool.
        (Currency c0, Currency c1) = _sorted(token0(), token1());
        PoolKey memory key = PoolKey({
            currency0: c0, currency1: c1, fee: DYNAMIC_FEE, tickSpacing: tickSpacing(), hooks: IHooks(address(hook))
        });
        uint160 sqrtPriceX96 = uint160(vm.envOr("SQRT_PRICE_X96", uint256(79228162514264337593543950336))); // 1:1
        IPoolManager(poolManager()).initialize(key, sqrtPriceX96);

        // invertedPair=true when deploying a USDC/WETH pool where USDC (token0) is the stable
        // and WETH (token1) is the volatile asset. Set the env var to override.
        bool invertedPair = vm.envOr("INVERTED_PAIR", false);
        hook.configurePool(key, tickLower(), tickUpper(), tau(), hedgeRatioWad(), invertedPair);

        // Fund LPs in token1 (the numéraire leg, e.g. USDC).
        funding.registerPool(PoolId.unwrap(key.toId()), Currency.unwrap(c1));

        address vault = address(0);
        if (reserveAsset() != address(0)) {
            vault = address(new InsuranceVault(reserveAsset(), coverer(), owner()));
        }

        vm.stopBroadcast();

        console2.log("LambdaHook     ", address(hook));
        console2.log("Funding        ", address(funding));
        console2.log("InsuranceVault ", vault);
        console2.log("salt           ", vm.toString(salt));
        console2.log("poolId         ", vm.toString(PoolId.unwrap(key.toId())));
        console2.log("HedgeRequested topic0", vm.toString(_hedgeTopic()));
    }

    function _sorted(address a, address b) internal pure returns (Currency, Currency) {
        return a < b ? (Currency.wrap(a), Currency.wrap(b)) : (Currency.wrap(b), Currency.wrap(a));
    }

    function _hedgeTopic() internal pure returns (bytes32) {
        return keccak256("HedgeRequested(bytes32,uint64,uint256,uint256,uint160,uint256)");
    }
}
