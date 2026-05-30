// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LambdaHedgeReceiver} from "../src/LambdaHedgeReceiver.sol";

/// @notice The testnet receiver mirrors the hedger's auth + nonce semantics without a perp order.
contract LambdaHedgeReceiverTest is Test {
    LambdaHedgeReceiver internal receiver;
    address internal proxy = address(this); // authorized callback sender for the test
    address internal stranger = address(0xBEEF);
    bytes32 internal constant POOL = bytes32(uint256(1));

    event HedgeReceived(bytes32 indexed poolId, uint64 indexed nonce, uint256 targetSize, uint160 sqrtPriceX96);

    function setUp() public {
        // Deploy with this test as the authorized callback sender so it can drive applyHedge.
        receiver = new LambdaHedgeReceiver(proxy);
    }

    function test_applyHedge_recordsAndEmits() public {
        vm.expectEmit(true, true, false, true);
        emit HedgeReceived(POOL, 1, 5e18, uint160(1 << 96));
        receiver.applyHedge(address(0), POOL, 1, 5e18, uint160(1 << 96));

        LambdaHedgeReceiver.Hedge memory h = receiver.hedge(POOL);
        assertEq(h.lastNonce, 1, "nonce");
        assertEq(h.count, 1, "count");
        assertEq(h.targetSize, 5e18, "size");
    }

    function test_applyHedge_onlyAuthorizedSender() public {
        vm.prank(stranger);
        vm.expectRevert();
        receiver.applyHedge(address(0), POOL, 1, 5e18, uint160(1 << 96));
    }

    function test_applyHedge_dropsStaleNonce() public {
        receiver.applyHedge(address(0), POOL, 2, 5e18, uint160(1 << 96));
        vm.expectRevert(LambdaHedgeReceiver.StaleNonce.selector);
        receiver.applyHedge(address(0), POOL, 2, 9e18, uint160(1 << 96)); // replay
        vm.expectRevert(LambdaHedgeReceiver.StaleNonce.selector);
        receiver.applyHedge(address(0), POOL, 1, 9e18, uint160(1 << 96)); // out of order
    }

    function test_applyHedge_advancesOnHigherNonce() public {
        receiver.applyHedge(address(0), POOL, 1, 5e18, uint160(1 << 96));
        receiver.applyHedge(address(0), POOL, 4, 7e18, uint160(2 << 96));
        LambdaHedgeReceiver.Hedge memory h = receiver.hedge(POOL);
        assertEq(h.lastNonce, 4, "advanced");
        assertEq(h.count, 2, "count");
        assertEq(h.targetSize, 7e18, "latest size");
    }

    function test_checkpointFunding_onlyAuthorized() public {
        vm.prank(stranger);
        vm.expectRevert();
        receiver.checkpointFunding(address(0));
        receiver.checkpointFunding(address(0)); // authorized: no revert
    }
}
