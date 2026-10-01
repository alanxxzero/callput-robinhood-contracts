// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ITradingAccount} from "./interfaces/ITradingAccount.sol";
import {ITradingAccountFactory} from "./interfaces/ITradingAccountFactory.sol";

interface IOptionsMarketLookup {
    function getOptionsTokenByIndex(uint16 underlyingAssetIndex) external view returns (address);
    function indexToUnderlyingAsset(uint16 underlyingAssetIndex) external view returns (address);
    function mainStableAsset() external view returns (address);
}

interface IPositionManagerLike {
    function createOpenPosition(
        uint16 underlyingAssetIndex,
        uint8 length,
        bool[4] memory isBuys,
        bytes32[4] memory optionIds,
        bool[4] memory isCalls,
        uint256 minSize,
        address[] memory path,
        uint256 amountIn,
        uint256 minOutWhenSwap,
        address leadTrader
    ) external payable returns (bytes32);

    function createClosePosition(
        uint16 underlyingAssetIndex,
        uint256 optionTokenId,
        uint256 size,
        address[] memory path,
        uint256 minAmountOut,
        uint256 minOutWhenSwap,
        bool withdrawNAT
    ) external payable returns (bytes32);
}

interface ISettleManagerLike {
    function settlePosition(
        address[] memory path,
        uint16 underlyingAssetIndex,
        uint256 optionTokenId,
        uint256 minOutWhenSwap,
        bool withdrawNAT
    ) external returns (uint256);
}

interface IReferralLookup {
    function setParent(address parent) external;
}

/// @title TradingAccountImpl (v2)
/// @notice Beacon implementation of a per-user trading account. It holds USDC / native / ERC1155
///         positions, exposes owner-only withdrawals, and (v2) trades against the core protocol with
///         its own `msg.sender`: owner-only `openPosition` / `closePosition` (self-funded — the owner
///         attaches the native execution fee) and permissionless `settleExpired`.
/// @dev Storage rules (F7): append-only, no stateful reinitializer ever, every new field must be safe
///      at its zero value. `epoch` is reserved for M5 session keys. Layout snapshot lives in
///      `test/foundry/account/snapshots/TradingAccountImpl.storage.json`.
///      F2: the ERC1155 receiver hooks and `receive()` must never revert in any future version.
///      All withdrawals are owner-only and are not subject to any pause / safe-mode.
///      v2 appends NO storage: the trading entry points are stateless, so the v1 layout is untouched.
///
///      Cancellations / recovery (M3-2 core): this account can never call the core `cancel*` functions
///      (`PositionManager` gates them on `msg.sender == address(this)`). A request that the keeper
///      neither executes nor cancels is cleaned up by a registered position keeper via
///      `PositionManager.recoverExpiredRequest(key, isOpen)`. Principal/positions return to this
///      account and the execution fee goes to the keeper. A failed return reverts recovery;
///      retry the same request after the transfer can succeed. Returned funds leave through the
///      ordinary owner-only `withdraw*` functions.
contract TradingAccountImpl is ITradingAccount, IERC1155Receiver, Initializable {
    using SafeERC20 for IERC20;

    /// @notice Only immutable of the implementation; every core address is read from the factory.
    address public immutable override FACTORY;

    address internal constant NATIVE = address(0);
    uint256 private constant _NOT_ENTERED = 0;
    uint256 private constant _ENTERED = 1;

    // ------------------------------------------------------------------
    // storage (slot 0 is Initializable: _initialized uint8 + _initializing bool)
    // ------------------------------------------------------------------

    /// @dev slot 1
    uint256 private _reentrancyStatus;
    /// @dev slot 2 (packed) — owner is fixed for the life of the account (no transfer / recovery in v1).
    address public override owner;
    uint96 public override subIndex;
    /// @dev slot 3 — reserved for M5 (session-key epoch). Unused in v1, zero is the safe value.
    uint256 public override epoch;
    /// @dev slot 4 — last balance observed by this contract per token (address(0) = native).
    ///      Event-only checkpoint for `recordExternalDeposit`; never used for accounting.
    mapping(address => uint256) public override balanceCheckpoint;
    /// @dev slots 5..49 reserved.
    uint256[45] private __gap;

    // ------------------------------------------------------------------
    // modifiers
    // ------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != FACTORY) revert NotFactory();
        _;
    }

    modifier nonReentrant() {
        if (_reentrancyStatus == _ENTERED) revert Reentrancy();
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ------------------------------------------------------------------
    // constructor / initializer
    // ------------------------------------------------------------------

    constructor(address factory_) {
        if (factory_ == address(0)) revert ZeroAddress();
        FACTORY = factory_;
        _disableInitializers();
    }

    /// @notice Called by the factory in the same transaction as the CREATE2 deploy (F5).
    ///         No referral interaction here (F3).
    function initialize(address owner_, uint96 subIndex_) external override initializer onlyFactory {
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
        subIndex = subIndex_;
    }

    function version() external pure virtual override returns (uint256) {
        return 2;
    }

    // ------------------------------------------------------------------
    // deposits (owner only; the factory hub enforces safe-mode and registration)
    // ------------------------------------------------------------------

    function deposit(uint256 amount) external override onlyOwner nonReentrant {
        _deposit(amount);
    }

    /// @notice Permit front-run / replay tolerant: a failed permit falls back to the existing allowance.
    function depositWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
        onlyOwner
        nonReentrant
    {
        address usdc = _factory().USDC();
        // solhint-disable-next-line no-empty-blocks
        try IERC20Permit(usdc).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        _deposit(amount);
    }

    function _deposit(uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        ITradingAccountFactory factory = _factory();
        address usdc = factory.USDC();
        _settleExternalDelta(usdc, 0);
        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        balanceCheckpoint[usdc] = IERC20(usdc).balanceOf(address(this));
        factory.onDeposited(usdc, amount, msg.sender);
    }

    /// @notice Factory-side deposits (`createAccountAndDeposit`) transfer `amount` directly to this
    ///         address and then call this: any balance beyond `checkpoint + amount` is an unrecorded
    ///         external deposit and is emitted before the checkpoint moves.
    function syncCheckpoint(address token, uint256 amountJustReceived) external override onlyFactory {
        _settleExternalDelta(token, amountJustReceived);
    }

    // ------------------------------------------------------------------
    // withdrawals (owner only, never pausable)
    // ------------------------------------------------------------------

    function withdraw(address token, uint256 amount, address to) external override onlyOwner nonReentrant {
        _withdrawToken(token, amount, to);
    }

    function _withdrawToken(address token, uint256 amount, address to) internal {
        if (token == NATIVE) revert UseWithdrawNative();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _settleExternalDelta(token, 0);
        IERC20(token).safeTransfer(to, amount);
        balanceCheckpoint[token] = IERC20(token).balanceOf(address(this));
        _factory().onWithdrawn(token, amount, to);
    }

    function withdrawNative(uint256 amount, address payable to) external override onlyOwner nonReentrant {
        _withdrawNative(amount, to);
    }

    function _withdrawNative(uint256 amount, address payable to) internal {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _settleExternalDelta(NATIVE, 0);
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert NativeTransferFailed();
        balanceCheckpoint[NATIVE] = address(this).balance;
        _factory().onWithdrawn(NATIVE, amount, to);
    }

    /// @notice Withdraw an options position; the OptionsToken is resolved from the tokenId's
    ///         underlying-asset index via OptionsMarket.
    function withdrawPosition(uint256 tokenId, uint256 amount, address to) external override onlyOwner nonReentrant {
        address token = IOptionsMarketLookup(_factory().OPTIONS_MARKET()).getOptionsTokenByIndex(
            uint16(tokenId >> 240)
        );
        if (token == address(0)) revert UnknownOptionsToken(tokenId);
        _withdrawERC1155(token, tokenId, amount, to);
    }

    /// @notice Generic ERC1155 escape hatch (F8) for anything `withdrawPosition` cannot resolve.
    function withdrawERC1155(address token, uint256 id, uint256 amount, address to)
        external
        override
        onlyOwner
        nonReentrant
    {
        if (token == address(0)) revert ZeroAddress();
        _withdrawERC1155(token, id, amount, to);
    }

    function _withdrawERC1155(address token, uint256 id, uint256 amount, address to) internal {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        IERC1155(token).safeTransferFrom(address(this), to, id, amount, "");
        _factory().onPositionWithdrawn(token, id, amount, to);
    }

    // ------------------------------------------------------------------
    // trading (v2) — self-funded: the owner attaches the native execution fee as msg.value
    // ------------------------------------------------------------------

    /// @notice Opens a position through the core PositionManager with this account as the trader.
    /// @dev F0 owner-only, F1 `leadTrader = address(0)` (the account can never route a rebate to a
    ///      wallet), and the factory `canOpen` gate (safe-mode + registration + open allowlist) is
    ///      re-checked on every open. `msg.value` must equal the core `executionFee`; the core
    ///      enforces that exactly, so nothing is left behind here and no refund path is needed.
    ///      The Controller allowance is set to `amountIn` and reset to zero in the same call —
    ///      no standing approval ever survives this function (§M3 "no infinite approve").
    /// @param source Soft classification of the entry path (see `shared` `TradeSource`: 0 trading,
    ///      1 copy trading, 2 prediction). Display / points metadata only, emitted through the hub;
    ///      it is caller-supplied and MUST NOT be used as the basis of any on-chain benefit (§4.5).
    function openPosition(
        uint16 underlyingAssetIndex,
        uint8 length,
        bool[4] calldata isBuys,
        bytes32[4] calldata optionIds,
        bool[4] calldata isCalls,
        uint256 minSize,
        address[] calldata path,
        uint256 amountIn,
        uint256 minOutWhenSwap,
        uint8 source
    ) external payable override onlyOwner nonReentrant returns (bytes32 requestKey) {
        return _openPosition(underlyingAssetIndex, length, isBuys, optionIds, isCalls, minSize, path,
            amountIn, minOutWhenSwap, source);
    }

    function _openPosition(
        uint16 underlyingAssetIndex,
        uint8 length,
        bool[4] memory isBuys,
        bytes32[4] memory optionIds,
        bool[4] memory isCalls,
        uint256 minSize,
        address[] memory path,
        uint256 amountIn,
        uint256 minOutWhenSwap,
        uint8 source
    ) internal returns (bytes32 requestKey) {
        ITradingAccountFactory factory = _factory();
        if (!factory.canOpen(address(this))) revert OpenNotAllowed();
        if (path.length == 0) revert InvalidPath();

        address payToken = path[0];
        // report anything that arrived outside our entry points before the balance moves
        _settleExternalDelta(payToken, 0);

        address controller = factory.CONTROLLER();
        IERC20(payToken).forceApprove(controller, amountIn);
        requestKey = IPositionManagerLike(factory.POSITION_MANAGER()).createOpenPosition{value: msg.value}(
            underlyingAssetIndex,
            length,
            isBuys,
            optionIds,
            isCalls,
            minSize,
            path,
            amountIn,
            minOutWhenSwap,
            address(0) // F1
        );
        // exact approval: the core pulled `amountIn`, anything else would be a standing allowance
        if (IERC20(payToken).allowance(address(this), controller) != 0) {
            IERC20(payToken).forceApprove(controller, 0);
        }
        // the payment left this account inside this call; keep the checkpoint in step so a later
        // external deposit is still detected (payouts arrive asynchronously and are reported then)
        balanceCheckpoint[payToken] = IERC20(payToken).balanceOf(address(this));

        factory.onRequestTagged(requestKey, true, source);
    }

    /// @notice Requests a (partial or full) close of an expiring-later position.
    /// @dev Owner-only. Deliberately NOT gated by `canOpen`: safe-mode and the allowlist stop new
    ///      risk, they must never trap an open position. The ERC1155 lot is pulled by the Controller,
    ///      which is a handler of OptionsToken, so no ERC1155 approval exists or is needed.
    ///      `withdrawNAT` is hardcoded false because this account uses USDC-only trading paths.
    function closePosition(
        uint16 underlyingAssetIndex,
        uint256 optionTokenId,
        uint256 size,
        address[] calldata path,
        uint256 minAmountOut,
        uint256 minOutWhenSwap,
        uint8 source
    ) external payable override onlyOwner nonReentrant returns (bytes32 requestKey) {
        return _closePosition(underlyingAssetIndex, optionTokenId, size, path, minAmountOut,
            minOutWhenSwap, source);
    }

    function _closePosition(
        uint16 underlyingAssetIndex,
        uint256 optionTokenId,
        uint256 size,
        address[] memory path,
        uint256 minAmountOut,
        uint256 minOutWhenSwap,
        uint8 source
    ) internal returns (bytes32 requestKey) {
        ITradingAccountFactory factory = _factory();
        requestKey = IPositionManagerLike(factory.POSITION_MANAGER()).createClosePosition{value: msg.value}(
            underlyingAssetIndex,
            optionTokenId,
            size,
            path,
            minAmountOut,
            minOutWhenSwap,
            false
        );
        factory.onRequestTagged(requestKey, false, source);
    }

    /// @notice Settles expired option lots held by this account. Permissionless — a keeper or any
    ///         third party may call it — because every argument the core would let a caller choose is
    ///         derived on-chain here (F6): the payout token comes from the token id's strategy, the
    ///         path has length 1 (no swap, no MEV surface), `withdrawNAT` is false, and the core pays
    ///         `msg.sender`, which is this account. A caller can therefore never redirect the payout
    ///         nor change the token it is paid in. Owner-specified settlement (swaps) is out of scope.
    /// @dev All-or-nothing (v6), the same as the core's `SettleManager.settlePositions`: every
    ///      listed lot settles or the whole call reverts with the core's own revert data (settle
    ///      price missing, lot not expired, zero balance, unknown asset index, gas price above the
    ///      core's cap, out of gas). A duplicate id reverts: its second pass finds a zero balance.
    ///      An empty list reverts with `ZeroAmount`. A call that returns has settled every listed
    ///      lot. A reverted call changes nothing; the lots stay here and can be retried.
    /// @return amountsOut payout per id, in list order
    /// @return settled true for every entry; kept so existing decoders do not change
    function settleExpired(uint256[] calldata optionTokenIds)
        external
        override
        nonReentrant
        returns (uint256[] memory amountsOut, bool[] memory settled)
    {
        uint256 len = optionTokenIds.length;
        if (len == 0) revert ZeroAmount();
        amountsOut = new uint256[](len);
        settled = new bool[](len);

        ITradingAccountFactory factory = _factory();
        address optionsMarket = factory.OPTIONS_MARKET();
        address settleManager = factory.SETTLE_MANAGER();

        for (uint256 i = 0; i < len; ) {
            uint256 tokenId = optionTokenIds[i];
            uint16 assetIndex = uint16(tokenId >> 240);
            address[] memory path = new address[](1);
            path[0] = _settleQuoteToken(optionsMarket, tokenId, assetIndex);
            // proceeds land in this account during the call, so keep the checkpoint honest:
            // emit anything that arrived from outside first, then absorb the payout silently
            _settleExternalDelta(path[0], 0);
            amountsOut[i] = ISettleManagerLike(settleManager).settlePosition(path, assetIndex, tokenId, 0, false);
            settled[i] = true;
            balanceCheckpoint[path[0]] = IERC20(path[0]).balanceOf(address(this));

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Mirrors `Controller._validateQuoteToken` for the settle case: naked calls settle in the
    ///      underlying asset, everything else (including every spread) in the main stable asset.
    ///      Strategy bits: `Utils.parseOptionTokenId` -> BuyCall = 1, SellCall = 2.
    function _settleQuoteToken(address optionsMarket, uint256 tokenId, uint16 assetIndex)
        internal
        view
        returns (address)
    {
        uint8 strategy = uint8((tokenId >> 196) & 0xF);
        if (strategy == 1 || strategy == 2) {
            return IOptionsMarketLookup(optionsMarket).indexToUnderlyingAsset(assetIndex);
        }
        return IOptionsMarketLookup(optionsMarket).mainStableAsset();
    }

    // ------------------------------------------------------------------
    // referral (owner only)
    // ------------------------------------------------------------------

    /// @notice Selects this account's referrer independently of its owner's wallet referral.
    /// @dev Referral sees this account as msg.sender and enforces its existing one-time and
    ///      relationship rules. Failures revert; a device key or third party cannot select a parent.
    ///      Keep the existing factory callback/event so its deployed ABI and indexers stay compatible.
    function setReferral(address parent) external override onlyOwner nonReentrant {
        ITradingAccountFactory factory = _factory();
        IReferralLookup(factory.REFERRAL()).setParent(parent);
        factory.onReferralSynced(parent);
    }

    // ------------------------------------------------------------------
    // permissionless helpers
    // ------------------------------------------------------------------

    /// @notice Emits `ExternalDeposit` for any balance growth not produced by this contract's own
    ///         entry points (direct transfers, CCTP mints). Event-only; never moves funds.
    /// @param token ERC20 address, or address(0) for native.
    function recordExternalDeposit(address token) external override returns (uint256 delta) {
        return _settleExternalDelta(token, 0);
    }

    /// @dev Single place that moves the checkpoint. Everything above `checkpoint + excluded` is balance
    ///      that no entry point of this contract accounted for, so it is emitted as `ExternalDeposit`
    ///      before the checkpoint is overwritten — an unrecorded delta can never be silently absorbed
    ///      by a later deposit / withdrawal.
    function _settleExternalDelta(address token, uint256 excluded) internal returns (uint256 delta) {
        uint256 current = _balance(token);
        uint256 known = balanceCheckpoint[token] + excluded;
        balanceCheckpoint[token] = current;
        if (current > known) {
            delta = current - known;
            _factory().onExternalDeposit(token, delta);
        }
    }

    // ------------------------------------------------------------------
    // receivers — F2: must never revert, in this or any future version
    // ------------------------------------------------------------------

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    receive() external payable {}

    // ------------------------------------------------------------------
    // internals
    // ------------------------------------------------------------------

    function _factory() internal view returns (ITradingAccountFactory) {
        return ITradingAccountFactory(FACTORY);
    }

    function _balance(address token) internal view returns (uint256) {
        return token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

}
