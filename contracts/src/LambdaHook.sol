// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import {DeltaMath} from "./libraries/DeltaMath.sol";
import {DirectionalFee} from "./libraries/DirectionalFee.sol";
import {IShareCallback} from "./interfaces/IShareCallback.sol";

/// @title LambdaHook
/// @notice The Unichain leg of Lambda (README §"How Lambda works ①"). A Uniswap v4
///         hook that doubles as the protocol's liquidity vault: LPs `deposit`/`withdraw`
///         through it, the hook owns a single concentrated position per pool, and on
///         every swap it recomputes the position's *exact* delta and emits a
///         {HedgeRequested} event the moment that delta drifts past the re-hedge band τ.
///
/// @dev    Design contract with the rest of the system:
///
///         • The trading curve is never touched. The hook adds no swap delta and no
///           fee override — protection is entirely off-pool (the perp short). All it
///           does on `afterSwap` is read the post-swap price and maybe raise a signal.
///
///         • The hook is the *sole* liquidity provider to its pools. Direct
///           `modifyLiquidity` by anyone else is rejected (`beforeAddLiquidity` /
///           `beforeRemoveLiquidity`), so the vault's tracked liquidity is always the
///           pool's liquidity over the managed range — which is what makes the delta in
///           {HedgeRequested} exact rather than approximate.
///
///         • {HedgeRequested} is the only cross-chain trigger. It carries a per-pool
///           monotonic `nonce`; the Reactive SC and the HyperEVM hedger consume nonces
///           strictly in order, which is the hook's half of the "authenticated on both
///           legs" guarantee (README §Security). The hook never calls another chain
///           itself — it only emits.
///
///         • Delta math lives in {DeltaMath} and is settlement-grade (cross-checked
///           against Uniswap's own `getAmount0Delta`). `hedgedDelta` stores the raw LP
///           delta at the last signal; the event ships `targetSize = h · liveDelta` so
///           the hedger knows the short size directly.
///
/// @dev    Shares are intentionally non-transferable internal balances here. A transfer-
///         able ERC-20 wrapper (PerpShares) and per-LP funding accrual (Funding.sol) read
///         these balances; keeping them internal removes an attack surface from the leg
///         that custodies funds.
contract LambdaHook is IHooks, IUnlockCallback, Ownable, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // ─────────────────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Per-pool vault + hedge state.
    struct PoolState {
        bool initialized; // configurePool has run for this pool
        int24 tickLower; // managed position range (multiples of tickSpacing)
        int24 tickUpper;
        uint128 liquidity; // total managed liquidity owned by the vault
        uint256 totalShares; // LP shares outstanding against `liquidity`
        uint256 hedgeRatioWad; // h ∈ (0, 1e18]; default 0.65e18
        uint256 tau; // re-hedge band in token0 units (see DeltaMath.tauOptimal)
        uint256 hedgedDelta; // raw LP delta at the most recent HedgeRequested
        uint64 hedgeNonce; // strictly increasing per-pool signal counter
    }

    /// @notice Per-pool directional-fee state (Nezlobin LVR defense; see {DirectionalFee}).
    struct FeeState {
        bool set; // fee params seeded for this pool
        uint24 baseFeePips; // neutral fee when price is at the reference
        uint24 minFeePips; // floor for the discounted side
        uint24 maxSurchargePips; // cap on the directional add-on
        uint256 sensitivityPipsPerTick; // surcharge pips per tick of drift
        uint32 emaWeightBps; // EMA weight for the reference tick, in bps
        int24 refTick; // smoothed reference tick, updated each swap
    }

    /// @dev Discriminates the work done inside {unlockCallback}.
    enum Action {
        DEPOSIT,
        WITHDRAW
    }

    /// @dev ABI-encoded payload passed through `poolManager.unlock`.
    struct CallbackData {
        Action action;
        PoolKey key;
        address payer; // funds source on deposit
        address recipient; // funds destination on withdraw
        uint128 liquidity; // liquidity to add (deposit) or remove (withdraw)
        uint256 amount0Limit; // max owed (deposit) / min received (withdraw) of token0
        uint256 amount1Limit; // max owed (deposit) / min received (withdraw) of token1
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────

    IPoolManager public immutable poolManager;

    /// @notice Default hedge ratio applied at configuration time: Hane (2026) h* ≈ 0.65.
    uint256 public constant DEFAULT_HEDGE_RATIO = 0.65e18;

    // Default directional-fee parameters seeded at configuration (tunable via setFeeParams).
    uint24 internal constant DEFAULT_BASE_FEE = 3000; // 0.30%
    uint24 internal constant DEFAULT_MIN_FEE = 500; // 0.05%
    uint24 internal constant DEFAULT_MAX_SURCHARGE = 20_000; // 2.00%
    uint256 internal constant DEFAULT_FEE_SENSITIVITY = 50; // pips per tick of drift
    uint32 internal constant DEFAULT_EMA_WEIGHT_BPS = 2000; // 0.20 smoothing

    mapping(PoolId => PoolState) internal _pools;
    mapping(PoolId => mapping(address => uint256)) internal _shares;
    mapping(PoolId => FeeState) internal _fees;

    /// @notice Optional funding ledger notified on every share change; zero disables it.
    address public shareCallback;

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a pool is registered for vaulting + hedging.
    event PoolConfigured(PoolId indexed id, int24 tickLower, int24 tickUpper, uint256 tau, uint256 hedgeRatioWad);

    /// @notice Emitted when the owner retunes the re-hedge band or hedge ratio.
    event HedgeParamsUpdated(PoolId indexed id, uint256 tau, uint256 hedgeRatioWad);

    /// @notice Emitted when the funding-ledger callback target is set.
    event ShareCallbackSet(address indexed callback);

    /// @notice Emitted when the directional-fee parameters are seeded or retuned.
    event FeeParamsUpdated(
        PoolId indexed id, uint24 baseFeePips, uint24 minFeePips, uint24 maxSurchargePips, uint256 sensitivityPipsPerTick, uint32 emaWeightBps
    );

    /// @notice An LP added liquidity through the vault.
    event Deposited(PoolId indexed id, address indexed to, uint128 liquidity, uint256 shares, uint256 amount0, uint256 amount1);

    /// @notice An LP removed liquidity through the vault.
    event Withdrawn(PoolId indexed id, address indexed from, uint128 liquidity, uint256 shares, uint256 amount0, uint256 amount1);

    /// @notice The cross-chain hedge trigger. Consumed in `nonce` order by the Reactive SC.
    /// @param id          Pool whose hedge must change.
    /// @param nonce       Strictly increasing per-pool counter (replay protection).
    /// @param targetSize  New short size the hedger should hold = h · liveDelta (token0 units).
    /// @param liveDelta   Raw LP delta that triggered the signal (token0 units).
    /// @param sqrtPriceX96 Pool price at signal time (Q64.96), for the hedger's sanity checks.
    /// @param timestamp   Block time of the signal.
    event HedgeRequested(
        PoolId indexed id,
        uint64 indexed nonce,
        uint256 targetSize,
        uint256 liveDelta,
        uint160 sqrtPriceX96,
        uint256 timestamp
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error NotPoolManager();
    error PoolNotConfigured();
    error PoolAlreadyConfigured();
    error DirectLiquidityDisabled();
    error InvalidRange();
    error InvalidHedgeRatio();
    error ZeroLiquidity();
    error Slippage();
    error InsufficientShares();
    error NotDynamicFee();
    error InvalidFeeParams();
    error HookNotImplemented();

    // ─────────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────────

    constructor(IPoolManager _poolManager, address _owner) {
        poolManager = _poolManager;
        _initializeOwner(_owner);
        // Reverts unless this contract is deployed to an address whose low bits match
        // the permissions below — v4's compile-time-free way of binding code to flags.
        Hooks.validateHookPermissions(this, getHookPermissions());
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hook wiring
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    function _onlyPoolManager() internal view {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
    }

    /// @notice The four lifecycle points Lambda needs: gate the two liquidity paths so the
    ///         vault stays the only LP, and watch every swap to keep the hedge in band.
    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Register a pool: set the managed range and hedge parameters, and seed the
    ///         directional fee. Must run before the first deposit, and after the pool is
    ///         initialized (its current tick seeds the fee reference). The pool must use a
    ///         dynamic fee — otherwise v4 ignores the hook's fee override and the on-pool LVR
    ///         defense would be silently inert.
    /// @param key            The pool to manage (must be a dynamic-fee pool).
    /// @param tickLower      Lower bound of the vault's single position.
    /// @param tickUpper      Upper bound of the vault's single position.
    /// @param tau            Initial re-hedge band in token0 units (see {DeltaMath.tauOptimal}).
    /// @param hedgeRatioWad  Hedge ratio h in WAD; 0 selects {DEFAULT_HEDGE_RATIO}.
    function configurePool(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint256 tau, uint256 hedgeRatioWad)
        external
        onlyOwner
    {
        PoolId id = key.toId();
        PoolState storage ps = _pools[id];
        if (ps.initialized) revert PoolAlreadyConfigured();
        if (!LPFeeLibrary.isDynamicFee(key.fee)) revert NotDynamicFee();
        if (tickLower >= tickUpper) revert InvalidRange();
        if (tickLower % key.tickSpacing != 0 || tickUpper % key.tickSpacing != 0) revert InvalidRange();

        if (hedgeRatioWad == 0) hedgeRatioWad = DEFAULT_HEDGE_RATIO;
        if (hedgeRatioWad > DeltaMath.WAD) revert InvalidHedgeRatio();

        ps.initialized = true;
        ps.tickLower = tickLower;
        ps.tickUpper = tickUpper;
        ps.tau = tau;
        ps.hedgeRatioWad = hedgeRatioWad;

        // Seed the directional fee with defaults, anchoring its reference at the live tick.
        (, int24 tick,,) = poolManager.getSlot0(id);
        FeeState storage f = _fees[id];
        f.set = true;
        f.baseFeePips = DEFAULT_BASE_FEE;
        f.minFeePips = DEFAULT_MIN_FEE;
        f.maxSurchargePips = DEFAULT_MAX_SURCHARGE;
        f.sensitivityPipsPerTick = DEFAULT_FEE_SENSITIVITY;
        f.emaWeightBps = DEFAULT_EMA_WEIGHT_BPS;
        f.refTick = tick;

        emit PoolConfigured(id, tickLower, tickUpper, tau, hedgeRatioWad);
        emit FeeParamsUpdated(id, DEFAULT_BASE_FEE, DEFAULT_MIN_FEE, DEFAULT_MAX_SURCHARGE, DEFAULT_FEE_SENSITIVITY, DEFAULT_EMA_WEIGHT_BPS);
    }

    /// @notice Set (or clear, with the zero address) the funding ledger notified on share
    ///         changes. The target must implement {IShareCallback}.
    function setShareCallback(address callback) external onlyOwner {
        shareCallback = callback;
        emit ShareCallbackSet(callback);
    }

    /// @notice Retune the directional-fee parameters for a configured pool.
    /// @dev    Requires minFee ≤ baseFee, both ≤ MAX_LP_FEE, and an EMA weight in (0, 1].
    function setFeeParams(
        PoolKey calldata key,
        uint24 baseFeePips,
        uint24 minFeePips,
        uint24 maxSurchargePips,
        uint256 sensitivityPipsPerTick,
        uint32 emaWeightBps
    ) external onlyOwner {
        PoolId id = key.toId();
        FeeState storage f = _fees[id];
        if (!f.set) revert PoolNotConfigured();
        if (
            minFeePips > baseFeePips || baseFeePips > DirectionalFee.MAX_LP_FEE
                || maxSurchargePips > DirectionalFee.MAX_LP_FEE || emaWeightBps == 0 || emaWeightBps > 10_000
        ) revert InvalidFeeParams();

        f.baseFeePips = baseFeePips;
        f.minFeePips = minFeePips;
        f.maxSurchargePips = maxSurchargePips;
        f.sensitivityPipsPerTick = sensitivityPipsPerTick;
        f.emaWeightBps = emaWeightBps;

        emit FeeParamsUpdated(id, baseFeePips, minFeePips, maxSurchargePips, sensitivityPipsPerTick, emaWeightBps);
    }

    /// @notice Retune the re-hedge band and hedge ratio without touching the range.
    function setHedgeParams(PoolKey calldata key, uint256 tau, uint256 hedgeRatioWad) external onlyOwner {
        PoolId id = key.toId();
        PoolState storage ps = _pools[id];
        if (!ps.initialized) revert PoolNotConfigured();
        if (hedgeRatioWad == 0) hedgeRatioWad = DEFAULT_HEDGE_RATIO;
        if (hedgeRatioWad > DeltaMath.WAD) revert InvalidHedgeRatio();
        ps.tau = tau;
        ps.hedgeRatioWad = hedgeRatioWad;
        emit HedgeParamsUpdated(id, tau, hedgeRatioWad);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LP entry / exit
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Add `liquidity` to the vault's position and mint proportional shares.
    /// @dev    The caller must have approved this contract for the ERC-20 legs; native
    ///         token0 is paid from `msg.value` and any surplus is refunded. The exact token
    ///         cost is whatever the PoolManager charges for the liquidity, bounded below by
    ///         the slippage limits.
    /// @param key        Configured pool.
    /// @param liquidity  Units of liquidity to add (front-ends convert token amounts → L).
    /// @param amount0Max Max token0 the caller will pay.
    /// @param amount1Max Max token1 the caller will pay.
    /// @param to         Recipient of the minted shares.
    /// @return shares    Shares minted to `to`.
    /// @return amount0   token0 actually paid.
    /// @return amount1   token1 actually paid.
    function deposit(PoolKey calldata key, uint128 liquidity, uint256 amount0Max, uint256 amount1Max, address to)
        external
        payable
        nonReentrant
        returns (uint256 shares, uint256 amount0, uint256 amount1)
    {
        PoolId id = key.toId();
        PoolState storage ps = _pools[id];
        if (!ps.initialized) revert PoolNotConfigured();
        if (liquidity == 0) revert ZeroLiquidity();

        uint128 liquidityBefore = ps.liquidity;
        uint256 sharesBefore = ps.totalShares;

        (amount0, amount1) = _unlock(Action.DEPOSIT, key, msg.sender, to, liquidity, amount0Max, amount1Max);

        // First deposit anchors shares 1:1 to liquidity; later deposits are pro-rata so a
        // share's claim on the position never changes underneath existing LPs.
        shares = liquidityBefore == 0
            ? liquidity
            : FixedPointMathLib.fullMulDiv(liquidity, sharesBefore, liquidityBefore);

        ps.liquidity = liquidityBefore + liquidity;
        ps.totalShares = sharesBefore + shares;
        uint256 sharesOld = _shares[id][to];
        _shares[id][to] = sharesOld + shares;
        _notifyShares(id, to, sharesOld, sharesOld + shares);

        // Refund any native surplus (token0 paid from msg.value).
        if (address(this).balance > 0) SafeTransferLib.safeTransferETH(msg.sender, address(this).balance);

        emit Deposited(id, to, liquidity, shares, amount0, amount1);
        _syncHedge(ps, id);
    }

    /// @notice Burn `shares` and withdraw the proportional slice of the vault's position.
    /// @param key        Configured pool.
    /// @param shares     Shares to burn.
    /// @param amount0Min Min token0 the caller will accept.
    /// @param amount1Min Min token1 the caller will accept.
    /// @param to         Recipient of the withdrawn tokens (and any accrued LP fees).
    /// @return amount0   token0 returned.
    /// @return amount1   token1 returned.
    function withdraw(PoolKey calldata key, uint256 shares, uint256 amount0Min, uint256 amount1Min, address to)
        external
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        PoolId id = key.toId();
        PoolState storage ps = _pools[id];
        if (!ps.initialized) revert PoolNotConfigured();

        uint256 userShares = _shares[id][msg.sender];
        if (shares == 0 || shares > userShares) revert InsufficientShares();

        // liquidity to pull = shares' pro-rata slice, rounded down so the vault never
        // promises more liquidity than it holds.
        uint128 liquidity = uint128(FixedPointMathLib.fullMulDiv(shares, ps.liquidity, ps.totalShares));

        // Effects before the unlock interaction.
        _shares[id][msg.sender] = userShares - shares;
        ps.totalShares -= shares;
        ps.liquidity -= liquidity;
        _notifyShares(id, msg.sender, userShares, userShares - shares);

        (amount0, amount1) = _unlock(Action.WITHDRAW, key, msg.sender, to, liquidity, amount0Min, amount1Min);

        emit Withdrawn(id, msg.sender, liquidity, shares, amount0, amount1);
        _syncHedge(ps, id);
    }

    /// @dev Encode the work, open the PoolManager lock, and decode the settled amounts.
    ///      Isolating the {CallbackData} construction in its own frame keeps {deposit} and
    ///      {withdraw} clear of "stack too deep" without resorting to via-IR.
    function _unlock(
        Action action,
        PoolKey calldata key,
        address payer,
        address recipient,
        uint128 liquidity,
        uint256 limit0,
        uint256 limit1
    ) internal returns (uint256 amount0, uint256 amount1) {
        bytes memory res = poolManager.unlock(
            abi.encode(
                CallbackData({
                    action: action,
                    key: key,
                    payer: payer,
                    recipient: recipient,
                    liquidity: liquidity,
                    amount0Limit: limit0,
                    amount1Limit: limit1
                })
            )
        );
        (amount0, amount1) = abi.decode(res, (uint256, uint256));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Unlock callback — the only place liquidity is actually moved & settled
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        CallbackData memory cb = abi.decode(data, (CallbackData));

        int256 signed = cb.action == Action.DEPOSIT ? int256(uint256(cb.liquidity)) : -int256(uint256(cb.liquidity));

        PoolState storage ps = _pools[cb.key.toId()];
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            cb.key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: ps.tickLower,
                tickUpper: ps.tickUpper,
                liquidityDelta: signed,
                salt: bytes32(0)
            }),
            ""
        );

        if (cb.action == Action.DEPOSIT) {
            // Negative delta == amounts the vault owes the pool.
            uint256 owed0 = uint256(uint128(-delta.amount0()));
            uint256 owed1 = uint256(uint128(-delta.amount1()));
            if (owed0 > cb.amount0Limit || owed1 > cb.amount1Limit) revert Slippage();
            _settle(cb.key.currency0, cb.payer, owed0);
            _settle(cb.key.currency1, cb.payer, owed1);
            return abi.encode(owed0, owed1);
        } else {
            // Positive delta == amounts the pool owes the vault (principal + accrued fees).
            uint256 got0 = uint256(uint128(delta.amount0()));
            uint256 got1 = uint256(uint128(delta.amount1()));
            if (got0 < cb.amount0Limit || got1 < cb.amount1Limit) revert Slippage();
            _take(cb.key.currency0, cb.recipient, got0);
            _take(cb.key.currency1, cb.recipient, got1);
            return abi.encode(got0, got1);
        }
    }

    /// @dev Pay `amount` of `currency` into the PoolManager on behalf of `payer`.
    function _settle(Currency currency, address payer, uint256 amount) internal {
        if (amount == 0) return;
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            SafeTransferLib.safeTransferFrom(Currency.unwrap(currency), payer, address(poolManager), amount);
            poolManager.settle();
        }
    }

    /// @dev Pull `amount` of `currency` out of the PoolManager to `recipient`.
    function _take(Currency currency, address recipient, uint256 amount) internal {
        if (amount == 0) return;
        poolManager.take(currency, recipient, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Hedge signalling
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Recompute the live LP delta from the current price and, if it has drifted past
    ///      τ from the last hedged level, emit a fresh {HedgeRequested} and reset the band.
    function _syncHedge(PoolState storage ps, PoolId id) internal {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        uint256 live = DeltaMath.lpDelta(
            ps.liquidity,
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(ps.tickLower),
            TickMath.getSqrtPriceAtTick(ps.tickUpper)
        );

        if (DeltaMath.shouldRehedge(ps.hedgedDelta, live, ps.tau)) {
            ps.hedgedDelta = live;
            uint64 nonce = ++ps.hedgeNonce;
            emit HedgeRequested(id, nonce, DeltaMath.hedgeSize(live, ps.hedgeRatioWad), live, sqrtPriceX96, block.timestamp);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // IHooks — only the four enabled callbacks do anything; the rest revert if reached.
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Reject every LP that isn't the vault itself, keeping pool liquidity == vault liquidity.
    function beforeAddLiquidity(address sender, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        view
        onlyPoolManager
        returns (bytes4)
    {
        if (sender != address(this)) revert DirectLiquidityDisabled();
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @notice Same gate on removal.
    function beforeRemoveLiquidity(address sender, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        view
        onlyPoolManager
        returns (bytes4)
    {
        if (sender != address(this)) revert DirectLiquidityDisabled();
        return IHooks.beforeRemoveLiquidity.selector;
    }

    /// @notice Price the incoming swap with the Nezlobin directional fee (see {DirectionalFee}):
    ///         surcharge the trend-continuing (likely-informed) side, discount the reverting
    ///         side, by how far the live tick has drifted from the smoothed reference. Adds no
    ///         swap delta — only the fee is overridden, so the trading curve is untouched.
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        view
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId id = key.toId();
        FeeState storage f = _fees[id];
        if (!f.set) {
            // Unconfigured: no override (value without the flag leaves the pool's fee in place).
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        (, int24 tick,,) = poolManager.getSlot0(id);
        uint24 fee = DirectionalFee.asymmetricFee(
            f.baseFeePips, f.minFeePips, f.maxSurchargePips, f.sensitivityPipsPerTick, tick - f.refTick, params.zeroForOne
        );
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    /// @notice The watch point: every swap re-evaluates delta (may raise a hedge signal) and
    ///         nudges the directional-fee reference toward the new price. Returns a zero hook
    ///         delta — the trading curve is left exactly as Uniswap's.
    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        PoolState storage ps = _pools[id];
        if (ps.initialized) _syncHedge(ps, id);
        _updateFeeReference(id);
        return (IHooks.afterSwap.selector, int128(0));
    }

    /// @dev Notify the funding ledger (if configured) that an LP's shares changed, so it can
    ///      settle the holder before the balance moves. Best-effort wiring to our own trusted
    ///      contract; runs after share state is updated (checks-effects-interactions).
    function _notifyShares(PoolId id, address account, uint256 oldShares, uint256 newShares) internal {
        address cb = shareCallback;
        if (cb != address(0)) {
            IShareCallback(cb).onSharesChanged(PoolId.unwrap(id), account, oldShares, newShares);
        }
    }

    /// @dev EMA-update the fee reference tick toward the post-swap price:
    ///      refTick += (tick − refTick) · emaWeightBps / 10000.
    function _updateFeeReference(PoolId id) internal {
        FeeState storage f = _fees[id];
        if (!f.set) return;
        (, int24 tick,,) = poolManager.getSlot0(id);
        int256 step = (int256(tick) - int256(f.refTick)) * int256(uint256(f.emaWeightBps)) / 10_000;
        // The EMA moves refTick toward `tick` by a fraction, so it stays between the two
        // (both valid int24 ticks) — the narrowing cannot overflow int24.
        // forge-lint: disable-next-line(unsafe-typecast)
        f.refTick = int24(int256(f.refTick) + step);
    }

    // ── Disabled callbacks ────────────────────────────────────────────────────

    function beforeInitialize(address, PoolKey calldata, uint160) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert HookNotImplemented();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Full vault + hedge state for a pool.
    function poolState(PoolKey calldata key) external view returns (PoolState memory) {
        return _pools[key.toId()];
    }

    /// @notice Shares held by `account` in `key`'s vault.
    function sharesOf(PoolKey calldata key, address account) external view returns (uint256) {
        return _shares[key.toId()][account];
    }

    /// @notice The position's delta at the current price, in token0 units. This is the
    ///         quantity a full hedge would short; the live short target is `h ·` this.
    function currentDelta(PoolKey calldata key) external view returns (uint256) {
        PoolId id = key.toId();
        PoolState storage ps = _pools[id];
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(id);
        return DeltaMath.lpDelta(
            ps.liquidity, sqrtPriceX96, TickMath.getSqrtPriceAtTick(ps.tickLower), TickMath.getSqrtPriceAtTick(ps.tickUpper)
        );
    }

    /// @notice Directional-fee state (params + live reference tick) for a pool.
    function feeState(PoolKey calldata key) external view returns (FeeState memory) {
        return _fees[key.toId()];
    }

    /// @notice The fee a swap in `zeroForOne` would pay right now, in pips (no override flag).
    function previewFee(PoolKey calldata key, bool zeroForOne) external view returns (uint24) {
        PoolId id = key.toId();
        FeeState storage f = _fees[id];
        if (!f.set) return 0;
        (, int24 tick,,) = poolManager.getSlot0(id);
        return DirectionalFee.asymmetricFee(
            f.baseFeePips, f.minFeePips, f.maxSurchargePips, f.sensitivityPipsPerTick, tick - f.refTick, zeroForOne
        );
    }

    /// @dev Accept native refunds / settlements for native-token0 pools.
    receive() external payable {}
}
