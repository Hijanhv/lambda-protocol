// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ICoreWriter, CORE_WRITER} from "../interfaces/ICoreWriter.sol";

/// @title CoreWriterLib
/// @notice Builds and submits Hyperliquid CoreWriter actions for Lambda's perp hedge.
/// @dev    CoreWriter actions are length-framed: a 1-byte encoding version, a 3-byte action
///         id, then the ABI-encoded action tuple. Lambda only ever needs one action — a
///         limit order — which it uses to open, grow, shrink, or close the short.
///
///         Sizes and prices on Hyperliquid L1 are integers in the asset's native tick/lot
///         scale, not WAD; conversion from Lambda's token0 units is the hedger's job. This
///         library is pure framing so it can be unit-tested byte-for-byte and adjusted in
///         one place if the L1 action schema is versioned.
library CoreWriterLib {
    /// @notice Current CoreWriter encoding version (first byte of every action).
    uint8 internal constant ENCODING_VERSION = 1;

    /// @notice Action id for a limit order (open/resize/close a position).
    uint24 internal constant ACTION_LIMIT_ORDER = 1;

    /// @notice Time-in-force selector for the limit order, per the L1 schema.
    uint8 internal constant TIF_ALO = 1; // add-liquidity-only (post-only)
    uint8 internal constant TIF_GTC = 2; // good-til-cancelled
    uint8 internal constant TIF_IOC = 3; // immediate-or-cancel (taker)

    /// @notice A Hyperliquid L1 limit order. Sizes and prices are in the asset's native
    ///         integer scale; `reduceOnly` confines the order to shrinking the position.
    struct LimitOrder {
        uint32 asset; // L1 perp asset index (e.g. ETH-PERP)
        bool isBuy; // true = long, false = short (Lambda's hedge sells)
        uint64 limitPx; // limit price, L1 price units
        uint64 sz; // size, L1 size units
        bool reduceOnly; // order may only shrink the position
        uint8 tif; // time-in-force (TIF_ALO/TIF_GTC/TIF_IOC)
        uint128 cloid; // client order id for idempotency; 0 = none
    }

    /// @notice Frame a limit order into CoreWriter's raw-action encoding: version byte,
    ///         3-byte action id, then the ABI-encoded order tuple.
    function encodeLimitOrder(LimitOrder memory o) internal pure returns (bytes memory) {
        return abi.encodePacked(
            ENCODING_VERSION,
            bytes3(ACTION_LIMIT_ORDER),
            abi.encode(o.asset, o.isBuy, o.limitPx, o.sz, o.reduceOnly, o.tif, o.cloid)
        );
    }

    /// @notice Build and submit a limit order to the CoreWriter precompile in one call.
    function sendLimitOrder(LimitOrder memory o) internal {
        ICoreWriter(CORE_WRITER).sendRawAction(encodeLimitOrder(o));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action 7 — usdClassTransfer (spot ↔ perp margin)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Action id for moving USDC between the contract's spot balance and its
    ///         Core perp margin account. Pre-funding the contract's spot balance is not
    ///         enough to open perps — the contract itself must send this action to credit
    ///         its margin account. No EOA can do this on behalf of a contract.
    uint24 internal constant ACTION_USD_CLASS_TRANSFER = 7;

    /// @notice Parameters for a usdClassTransfer action.
    struct UsdClassTransfer {
        uint64 ntl; // amount in USDC notional units (Hyperliquid native scale)
        bool toPerp; // true = spot → perp margin; false = perp margin → spot
    }

    /// @notice Frame a usdClassTransfer action: version byte, 3-byte action id, ABI-encoded tuple.
    function encodeUsdClassTransfer(UsdClassTransfer memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            ENCODING_VERSION,
            bytes3(ACTION_USD_CLASS_TRANSFER),
            abi.encode(t.ntl, t.toPerp)
        );
    }

    /// @notice Build and submit a usdClassTransfer to the CoreWriter precompile in one call.
    function sendUsdClassTransfer(UsdClassTransfer memory t) internal {
        ICoreWriter(CORE_WRITER).sendRawAction(encodeUsdClassTransfer(t));
    }
}
