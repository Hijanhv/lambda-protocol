// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CoreWriterLib} from "../src/libraries/CoreWriterLib.sol";
import {ICoreWriter, CORE_WRITER} from "../src/interfaces/ICoreWriter.sol";

/// @notice Records the last raw action handed to the CoreWriter precompile.
contract MockCoreWriter is ICoreWriter {
    bytes public lastAction;
    uint256 public calls;

    function sendRawAction(bytes calldata data) external {
        lastAction = data;
        calls++;
    }
}

/// @notice Byte-exact tests for {CoreWriterLib}. The framing — 1-byte version, 3-byte action
///         id, ABI-encoded tuple — must match the L1 schema precisely, so we assert on the
///         literal bytes and on a clean round-trip rather than trusting the encoder blindly.
contract CoreWriterLibTest is Test {
    function _order() internal pure returns (CoreWriterLib.LimitOrder memory) {
        return CoreWriterLib.LimitOrder({
            asset: 1, // ETH-PERP, say
            isBuy: false, // short
            limitPx: 3500_000000, // arbitrary L1 price units
            sz: 12_3456,
            reduceOnly: false,
            tif: CoreWriterLib.TIF_IOC,
            cloid: uint128(0xABCDEF)
        });
    }

    function test_encode_hasVersionAndActionHeader() public pure {
        bytes memory data = CoreWriterLib.encodeLimitOrder(_order());
        // Header: version byte then 3-byte action id.
        assertEq(uint8(data[0]), CoreWriterLib.ENCODING_VERSION, "version byte");
        assertEq(uint8(data[1]), 0, "action id hi");
        assertEq(uint8(data[2]), 0, "action id mid");
        assertEq(uint8(data[3]), uint8(CoreWriterLib.ACTION_LIMIT_ORDER), "action id lo == 1");
        // 4-byte header + a 7-word ABI tuple.
        assertEq(data.length, 4 + 7 * 32, "header + 7 abi words");
    }

    function test_encode_roundTripsTuple() public pure {
        CoreWriterLib.LimitOrder memory o = _order();
        bytes memory data = CoreWriterLib.encodeLimitOrder(o);

        bytes memory body = new bytes(data.length - 4);
        for (uint256 i = 0; i < body.length; i++) {
            body[i] = data[i + 4];
        }
        (uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint8 tif, uint128 cloid) =
            abi.decode(body, (uint32, bool, uint64, uint64, bool, uint8, uint128));

        assertEq(asset, o.asset, "asset");
        assertEq(isBuy, o.isBuy, "isBuy");
        assertEq(limitPx, o.limitPx, "limitPx");
        assertEq(sz, o.sz, "sz");
        assertEq(reduceOnly, o.reduceOnly, "reduceOnly");
        assertEq(tif, o.tif, "tif");
        assertEq(cloid, o.cloid, "cloid");
    }

    function test_send_forwardsToPrecompile() public {
        vm.etch(CORE_WRITER, address(new MockCoreWriter()).code);
        CoreWriterLib.LimitOrder memory o = _order();

        CoreWriterLib.sendLimitOrder(o);

        assertEq(MockCoreWriter(CORE_WRITER).calls(), 1, "one action sent");
        assertEq(MockCoreWriter(CORE_WRITER).lastAction(), CoreWriterLib.encodeLimitOrder(o), "exact bytes forwarded");
    }
}
