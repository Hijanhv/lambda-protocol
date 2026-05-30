// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {LambdaConfig} from "./LambdaConfig.sol";
import {LambdaReactive} from "../src/LambdaReactive.sol";

/// @notice Deploys the Reactive Network brain: {LambdaReactive}, which subscribes to the
///         hook's HedgeRequested on the origin chain and routes callbacks to the HyperEVM
///         {LambdaHedger} on the destination chain.
/// @dev    Deploy this last — it needs both the hook and hedger addresses. Run against the
///         Reactive Network RPC: `forge script contracts/script/DeployReactive.s.sol --rpc-url $REACTIVE_RPC --broadcast`.
contract DeployReactive is LambdaConfig {
    function run() external {
        vm.startBroadcast();
        LambdaReactive reactive = new LambdaReactive(
            originChainId(), hookAddress(), destinationChainId(), hedgerAddress(), cronTopic(), callbackGasLimit()
        );
        vm.stopBroadcast();

        console2.log("LambdaReactive", address(reactive));
        console2.log("origin chain  ", originChainId());
        console2.log("dest chain    ", destinationChainId());
        console2.log("hook          ", hookAddress());
        console2.log("hedger        ", hedgerAddress());
    }
}
