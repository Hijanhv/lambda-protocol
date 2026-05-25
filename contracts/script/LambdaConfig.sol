// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";

/// @title LambdaConfig
/// @notice Shared deployment configuration for Lambda's three legs. Fixed system addresses
///         (the CoreWriter precompile, the Reactive service contract) are constants; every
///         chain-specific address and parameter is read from the environment so nothing is
///         hard-coded or fabricated. Each deploy script inherits this.
/// @dev    Set the env vars listed below before broadcasting. Addresses default to the zero
///         address where a script can run without them; the script reverts if a required one
///         is missing. See `DEPLOY.md` for the per-chain checklist.
abstract contract LambdaConfig is Script {
    // ── Fixed, audited system addresses ──────────────────────────────────────

    /// @notice Hyperliquid CoreWriter precompile on HyperEVM.
    address internal constant CORE_WRITER = 0x3333333333333333333333333333333333333333;

    /// @notice Reactive Network system contract (same address on RN and inside the ReactVM).
    address internal constant REACTIVE_SERVICE = 0x0000000000000000000000000000000000fffFfF;

    /// @notice Foundry's deterministic CREATE2 deployer — the deployer the hook miner targets.
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice Uniswap v4 dynamic-fee flag (required for the directional fee override).
    uint24 internal constant DYNAMIC_FEE = 0x800000;

    // ── Resolved per-deployment values ───────────────────────────────────────

    function owner() internal view returns (address) {
        return vm.envOr("OWNER", msg.sender);
    }

    // Unichain (the hook leg)
    function poolManager() internal view returns (address) {
        return vm.envAddress("POOL_MANAGER");
    }

    function token0() internal view returns (address) {
        return vm.envAddress("TOKEN0");
    }

    function token1() internal view returns (address) {
        return vm.envAddress("TOKEN1");
    }

    function tickSpacing() internal view returns (int24) {
        return int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
    }

    function tickLower() internal view returns (int24) {
        return int24(vm.envOr("TICK_LOWER", int256(-600)));
    }

    function tickUpper() internal view returns (int24) {
        return int24(vm.envOr("TICK_UPPER", int256(600)));
    }

    function tau() internal view returns (uint256) {
        return vm.envOr("TAU", uint256(1e15));
    }

    function hedgeRatioWad() internal view returns (uint256) {
        return vm.envOr("HEDGE_RATIO_WAD", uint256(0)); // 0 ⇒ contract default 0.65e18
    }

    // Reactive Network (the brain)
    function originChainId() internal view returns (uint256) {
        return vm.envUint("ORIGIN_CHAIN_ID");
    }

    function destinationChainId() internal view returns (uint256) {
        return vm.envUint("DESTINATION_CHAIN_ID");
    }

    function hookAddress() internal view returns (address) {
        return vm.envAddress("HOOK");
    }

    function hedgerAddress() internal view returns (address) {
        return vm.envAddress("HEDGER");
    }

    function cronTopic() internal view returns (uint256) {
        return vm.envOr("CRON_TOPIC", uint256(0)); // 0 disables cron
    }

    function callbackGasLimit() internal view returns (uint64) {
        return uint64(vm.envOr("CALLBACK_GAS_LIMIT", uint256(1_000_000)));
    }

    // HyperEVM (the hedge)
    function callbackSender() internal view returns (address) {
        return vm.envAddress("CALLBACK_SENDER"); // Reactive callback proxy on the destination chain
    }

    // Insurance reserve
    function reserveAsset() internal view returns (address) {
        return vm.envAddress("RESERVE_ASSET");
    }

    function coverer() internal view returns (address) {
        return vm.envOr("COVERER", msg.sender);
    }

    function aavePool() internal view returns (address) {
        return vm.envOr("AAVE_POOL", address(0)); // optional; 0 ⇒ reserve stays idle
    }

    function aToken() internal view returns (address) {
        return vm.envOr("ATOKEN", address(0));
    }
}
