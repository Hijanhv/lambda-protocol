// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AbstractCallback} from "reactive-lib/abstract-base/AbstractCallback.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "v4-core/src/libraries/FixedPoint96.sol";

import {CoreWriterLib} from "./libraries/CoreWriterLib.sol";

/// @title LambdaHedger
/// @notice The HyperEVM leg of Lambda (README §"How Lambda works ③"). It is the destination
///         of the Reactive Network callback: when the hook's delta drifts, {LambdaReactive}
///         routes a call here, and this contract turns the requested short *size* into a real
///         order on Hyperliquid's perpetuals via the CoreWriter precompile.
///
/// @dev    Two independent authorizations protect the money leg:
///           1. `authorizedSenderOnly` (from {AbstractCallback}) — only the Reactive callback
///              proxy registered at construction may invoke {applyHedge}.
///           2. Strictly increasing per-pool `nonce` — the same monotonic counter the hook
///              stamped on the event. A replayed or out-of-order callback is dropped. This is
///              the second half of "authenticated on both legs" (README §Security).
///
///         The contract holds the *target* short for each pool and only ever trades the
///         difference, so duplicate or coalesced signals converge to the right position
///         instead of stacking orders. Token0-denominated sizes/prices are converted to
///         Hyperliquid's integer lot/tick scale through per-market scales the owner sets —
///         that conversion is genuine per-asset calibration, kept in storage so it can be
///         tuned without redeploying. The byte framing of the order itself is in
///         {CoreWriterLib} and is unit-tested exactly.
contract LambdaHedger is AbstractCallback, Ownable {
    using FixedPointMathLib for uint256;

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Per-pool perp market calibration and live hedge state.
    struct Market {
        bool configured;
        uint32 asset; // Hyperliquid L1 perp asset index (e.g. ETH-PERP)
        uint256 szScaleWad; // token0 WAD amount → L1 size units (multiply, /1e18)
        uint256 pxScaleWad; // Uniswap mid (WAD) → L1 price units (multiply, /1e18)
        uint16 slippageBps; // taker price allowance, basis points
        uint8 tif; // CoreWriter time-in-force (see CoreWriterLib)
        uint256 shortSize; // current short, token0 WAD units
        uint64 lastNonce; // highest hook nonce applied
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────

    uint16 internal constant MAX_BPS = 10_000;

    mapping(bytes32 => Market) internal _markets;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice A pool's perp market was (re)calibrated.
    event MarketConfigured(
        bytes32 indexed poolId, uint32 asset, uint256 szScaleWad, uint256 pxScaleWad, uint16 slippageBps, uint8 tif
    );

    /// @notice A hedge callback was applied and an order was sent to CoreWriter.
    /// @param poolId    Pool whose hedge changed.
    /// @param nonce     Hook nonce that authorized this change.
    /// @param isBuy     true if the order reduced the short (buy back), false if it grew it.
    /// @param sizeWad   Size traded, token0 WAD units.
    /// @param newShort  Resulting short size, token0 WAD units.
    /// @param limitPx   L1 limit price used.
    event HedgeExecuted(
        bytes32 indexed poolId, uint64 indexed nonce, bool isBuy, uint256 sizeWad, uint256 newShort, uint64 limitPx
    );

    /// @notice A hedge callback that required no trade (target already met within rounding).
    event HedgeNoop(bytes32 indexed poolId, uint64 indexed nonce, uint256 shortSize);

    /// @notice Cron-driven funding checkpoint (per-LP accrual lives in Funding.sol).
    event FundingCheckpoint(address indexed rvmId, uint256 timestamp);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error MarketNotConfigured();
    error StaleNonce();
    error InvalidParams();

    // ─────────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────────

    /// @param callbackSender The Reactive callback proxy authorized to drive {applyHedge}.
    /// @param owner_         Admin permitted to calibrate markets.
    constructor(address callbackSender, address owner_) AbstractCallback(callbackSender) {
        _initializeOwner(owner_);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Calibrate (or recalibrate) the perp market backing a pool's hedge.
    function configureMarket(
        bytes32 poolId,
        uint32 asset,
        uint256 szScaleWad,
        uint256 pxScaleWad,
        uint16 slippageBps,
        uint8 tif
    ) external onlyOwner {
        if (szScaleWad == 0 || pxScaleWad == 0 || slippageBps > MAX_BPS) revert InvalidParams();
        Market storage m = _markets[poolId];
        m.configured = true;
        m.asset = asset;
        m.szScaleWad = szScaleWad;
        m.pxScaleWad = pxScaleWad;
        m.slippageBps = slippageBps;
        m.tif = tif;
        emit MarketConfigured(poolId, asset, szScaleWad, pxScaleWad, slippageBps, tif);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Reactive callback — the money leg
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Move this pool's short to `targetSize`, trading only the difference.
    /// @dev    Callable solely by the registered Reactive callback proxy. The leading
    ///         `rvmId` is injected by the relayer (Reactive callback ABI convention) and is
    ///         not trusted for authorization — the sender ACL and the nonce are.
    /// @param rvmId        Originating ReactVM id (relayer-supplied; informational).
    /// @param poolId       Pool whose hedge to update.
    /// @param nonce        Hook nonce; must exceed the last applied nonce for this pool.
    /// @param targetSize   Desired short size in token0 WAD units (= h · liveDelta).
    /// @param sqrtPriceX96 Pool price at signal time, used to price the taker order.
    function applyHedge(address rvmId, bytes32 poolId, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
        external
        authorizedSenderOnly
    {
        Market storage m = _markets[poolId];
        if (!m.configured) revert MarketNotConfigured();
        if (nonce <= m.lastNonce) revert StaleNonce();
        m.lastNonce = nonce;
        rvmId; // relayer-supplied, retained for ABI compatibility; not trusted for auth
        _rebalance(m, poolId, nonce, targetSize, sqrtPriceX96);
    }

    /// @dev Trade the difference between the current short and `targetSize`, sending at most
    ///      one CoreWriter order. Isolated in its own frame to keep {applyHedge} shallow.
    function _rebalance(Market storage m, bytes32 poolId, uint64 nonce, uint256 targetSize, uint160 sqrtPriceX96)
        internal
    {
        uint256 current = m.shortSize;
        if (targetSize == current) {
            emit HedgeNoop(poolId, nonce, current);
            return;
        }

        bool isBuy = targetSize < current; // buying back shrinks the short
        uint256 sizeWad = isBuy ? current - targetSize : targetSize - current;

        uint64 sz = _toUint64(FullMath.mulDiv(sizeWad, m.szScaleWad, 1e18));
        if (sz == 0) {
            // Difference rounds below one L1 lot — record the intent without an order.
            m.shortSize = targetSize;
            emit HedgeNoop(poolId, nonce, targetSize);
            return;
        }

        uint64 limitPx = _limitPrice(sqrtPriceX96, m.pxScaleWad, m.slippageBps, isBuy);
        // reduceOnly when buying back, so a hedge close can never flip the position long.
        CoreWriterLib.sendLimitOrder(
            CoreWriterLib.LimitOrder({
                asset: m.asset,
                isBuy: isBuy,
                limitPx: limitPx,
                sz: sz,
                reduceOnly: isBuy,
                tif: m.tif,
                cloid: _cloid(poolId, nonce)
            })
        );

        m.shortSize = targetSize;
        emit HedgeExecuted(poolId, nonce, isBuy, sizeWad, targetSize, limitPx);
    }

    /// @dev Deterministic client order id from (pool, nonce) for L1-side idempotency.
    function _cloid(bytes32 poolId, uint64 nonce) internal pure returns (uint128) {
        return uint128(uint256(keccak256(abi.encodePacked(poolId, nonce))));
    }

    /// @notice Cron-driven heartbeat for funding bookkeeping. Per-LP accrual is computed in
    ///         Funding.sol; here it only timestamps the cadence and is a no-op on positions.
    function checkpointFunding(address rvmId) external authorizedSenderOnly {
        emit FundingCheckpoint(rvmId, block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pricing helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Uniswap mid price (token1 per token0) in WAD from a Q64.96 sqrt price:
    ///      P = (sqrtP / 2^96)^2, computed without overflow via two mulDivs.
    function midPriceWad(uint160 sqrtPriceX96) public pure returns (uint256) {
        uint256 p = FullMath.mulDiv(uint256(sqrtPriceX96), uint256(sqrtPriceX96), FixedPoint96.Q96);
        return FullMath.mulDiv(p, 1e18, FixedPoint96.Q96);
    }

    /// @dev Convert the mid to an L1 limit price and bias it for a taker fill: a sell (growing
    ///      the short) prices below mid, a buy (reducing) prices above, by `slippageBps`.
    function _limitPrice(uint160 sqrtPriceX96, uint256 pxScaleWad, uint16 slippageBps, bool isBuy)
        internal
        pure
        returns (uint64)
    {
        uint256 px = FullMath.mulDiv(midPriceWad(sqrtPriceX96), pxScaleWad, 1e18);
        uint256 biased = isBuy
            ? FullMath.mulDiv(px, MAX_BPS + slippageBps, MAX_BPS)
            : FullMath.mulDiv(px, MAX_BPS - slippageBps, MAX_BPS);
        return _toUint64(biased);
    }

    function _toUint64(uint256 x) internal pure returns (uint64) {
        // Saturating cast: the ternary bounds `x` before the narrowing, so this is safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        return x > type(uint64).max ? type(uint64).max : uint64(x);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    function market(bytes32 poolId) external view returns (Market memory) {
        return _markets[poolId];
    }

    function shortSize(bytes32 poolId) external view returns (uint256) {
        return _markets[poolId].shortSize;
    }
}
