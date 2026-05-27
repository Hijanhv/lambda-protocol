// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {HookMiner} from "../script/HookMiner.sol";
import {LambdaHook} from "../src/LambdaHook.sol";

/// @notice Proves the deploy-time {HookMiner} produces an address whose permission bits match
///         Lambda's flags AND that {LambdaHook}'s constructor (which calls
///         `validateHookPermissions`) accepts it — i.e. a mined salt yields a deployable hook.
/// @dev    Uses `address(this)` as the CREATE2 deployer so the test can deploy via salted
///         `new` and land on the mined address (in scripts the deployer is Foundry's
///         deterministic CREATE2 factory; the algorithm is identical).
contract HookMinerTest is Test {
    function test_minesDeployableHookAddress() public {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.AFTER_SWAP_FLAG
        );
        IPoolManager pm = IPoolManager(address(0xCAFE));
        bytes memory args = abi.encode(pm, address(this));

        (address mined, bytes32 salt) = HookMiner.find(address(this), flags, type(LambdaHook).creationCode, args);

        assertEq(uint160(mined) & HookMiner.FLAG_MASK, flags, "mined address carries exactly Lambda's flags");

        // Deploying at the mined salt must succeed (constructor validates permissions) and land
        // precisely where the miner predicted.
        LambdaHook hook = new LambdaHook{salt: salt}(pm, address(this));
        assertEq(address(hook), mined, "deployed at the predicted address");
        assertEq(address(hook.poolManager()), address(pm), "constructor wired through");
    }

    function test_computeAddress_isDeterministic() public pure {
        bytes32 initHash = keccak256("x");
        address a = HookMiner.computeAddress(address(0xBEEF), bytes32(uint256(1)), initHash);
        address b = HookMiner.computeAddress(address(0xBEEF), bytes32(uint256(1)), initHash);
        assertEq(a, b, "same inputs => same address");
        assertTrue(
            a != HookMiner.computeAddress(address(0xBEEF), bytes32(uint256(2)), initHash), "salt changes address"
        );
    }
}
