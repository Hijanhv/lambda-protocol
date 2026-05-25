// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {LambdaConfig} from "./LambdaConfig.sol";
import {LambdaHedgeReceiver} from "../src/LambdaHedgeReceiver.sol";

/// @notice Deploys the testnet destination receiver on Unichain Sepolia (the Reactive callback
///         lands here because Lasna can't reach HyperEVM testnet — see DEPLOY_TESTNET.md).
///         Authorize it to the Unichain Sepolia callback proxy via `CALLBACK_SENDER`
///         (0x9299472A6399Fd1027ebF067571Eb3e3D7837FC4). Use the printed address as `HEDGER`
///         when deploying {LambdaReactive} with `DESTINATION_CHAIN_ID=1301`.
/// @dev    Run: `forge script contracts/script/DeployReceiver.s.sol --rpc-url $UNICHAIN_RPC --private-key $PRIVATE_KEY --broadcast`.
contract DeployReceiver is LambdaConfig {
    function run() external {
        vm.startBroadcast();
        LambdaHedgeReceiver receiver = new LambdaHedgeReceiver(callbackSender());
        vm.stopBroadcast();

        console2.log("LambdaHedgeReceiver", address(receiver));
        console2.log("callbackSender     ", callbackSender());
    }
}
