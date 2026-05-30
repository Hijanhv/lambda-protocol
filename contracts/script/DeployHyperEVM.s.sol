// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {LambdaConfig} from "./LambdaConfig.sol";
import {LambdaHedger} from "../src/LambdaHedger.sol";

/// @notice Deploys the HyperEVM hedge leg: {LambdaHedger}, authorized to the Reactive callback
///         proxy (`CALLBACK_SENDER`). Per-market calibration (asset, size/price scales) is set
///         afterwards via `configureMarket` once the pool id and L1 asset index are known.
/// @dev    Run: `forge script contracts/script/DeployHyperEVM.s.sol --rpc-url $HYPEREVM_RPC --broadcast`.
contract DeployHyperEVM is LambdaConfig {
    function run() external {
        vm.startBroadcast();
        LambdaHedger hedger = new LambdaHedger(callbackSender(), owner());
        vm.stopBroadcast();

        console2.log("LambdaHedger ", address(hedger));
        console2.log("callbackSender", callbackSender());
        console2.log("CoreWriter    ", CORE_WRITER);
    }
}
