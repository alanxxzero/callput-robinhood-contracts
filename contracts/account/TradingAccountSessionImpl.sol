// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TradingAccountImpl, IOptionsMarketLookup} from "./TradingAccountImpl.sol";
import {ITradingAccountSessions} from "./interfaces/ITradingAccountSessions.sol";
import {ITradingAccountFactory} from "./interfaces/ITradingAccountFactory.sol";
import {IReceiveWithAuthorization} from "./interfaces/IReceiveWithAuthorization.sol";
import {SessionHash} from "./SessionHash.sol";
import {SessionPolicy} from "./SessionPolicy.sol";
import {IController} from "../interfaces/IController.sol";

/// @notice Typed, bounded trading authority on the existing custody account. The sender pays fees;
///         it receives no owner privilege. Session keys cannot withdraw or modify authorization.
/// @dev Existing v2 storage (including gap) is untouched. Every appended field is safe at zero.
///      No session is enabled by an upgrade alone. No initializer or cached domain state.
///      v4: a grant may be installed before the account holds USDC; the first sponsored open
///      activates a directly funded account. An empty `underlyings` list permits every asset,
///      so one long-lived device approval keeps working when new assets are listed.
///      v5: the execution fee is not part of the signed intent. The sender forwards the core's
///      current fee as msg.value, bounded by the grant's per-trade and total fee caps.
///      Execution fees go to the processing keeper, including expired-request recovery.
///      v6: `settleExpired` reverts unless every listed lot settles (no per-item isolation).
contract TradingAccountSessionImpl is TradingAccountImpl, ITradingAccountSessions {
    uint256 public constant MAX_SESSION_DURATION = 180 days;
    uint16 public constant SESSION_STRATEGIES = 0x1e0; // four spreads, Utils.Strategy 5..8
    uint256 public constant MAX_UNDERLYINGS = 32;
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("CallPut Trading Account");
    bytes32 private constant VERSION_HASH = keccak256("1"); // authorization protocol, not impl version

    // Append at slot 50. Never reclaim v2's reserved gap or move these fields.
    mapping(bytes32 => SessionState) private _sessions;
    mapping(bytes32 => mapping(uint256 => uint256)) private _sessionNonces;
    mapping(uint256 => mapping(uint256 => uint256)) private _ownerNonces;
    mapping(uint256 => mapping(uint256 => bytes32)) private _grantNonces;
    // Retired v5 sponsor records. Never read, write or reuse this storage slot.
    mapping(bytes32 => address) private _feeSponsors;

    constructor(address factory_) TradingAccountImpl(factory_) {}

    function version() external pure virtual override returns (uint256) {
        return 6;
    }

    /// @notice Any gas payer may submit the owner's USDC authorization for this account.
    /// @dev Token, owner and receiver are fixed. ERC-3009 validates the exact amount,
    ///      window and token-scoped nonce. Registration failure rolls back the entire pull.
    function depositWithAuthorization(
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external override nonReentrant {
        if (amount == 0) revert ZeroAmount();
        ITradingAccountFactory factory = _factory();
        address usdc = factory.USDC();
        _settleExternalDelta(usdc, 0);
        uint256 beforeBalance = IERC20(usdc).balanceOf(address(this));
        IReceiveWithAuthorization(usdc).receiveWithAuthorization(
            owner, address(this), amount, validAfter, validBefore, nonce, signature
        );
        uint256 afterBalance = IERC20(usdc).balanceOf(address(this));
        if (afterBalance != beforeBalance + amount) revert InvalidFundingDelta();
        balanceCheckpoint[usdc] = afterBalance;
        factory.onDeposited(usdc, amount, owner);
    }

    function domainSeparator() public view override returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function _digest(bytes32 structHash) private view returns (bytes32) {
        return ECDSA.toTypedDataHash(domainSeparator(), structHash);
    }

    function hashGrant(Grant calldata g) external pure override returns (bytes32) {
        return SessionHash.grant(g);
    }

    function grantDigest(Grant calldata g) external view override returns (bytes32) {
        return _digest(SessionHash.grant(g));
    }

    function openDigest(Intent calldata i, Open calldata p) public view override returns (bytes32) {
        return _digest(SessionHash.intent(i, SessionHash.open(p), true));
    }

    function closeDigest(Intent calldata i, Close calldata p) public view override returns (bytes32) {
        return _digest(SessionHash.intent(i, SessionHash.close(p), false));
    }

    function withdrawalDigest(Withdrawal calldata p) public view override returns (bytes32) {
        return _digest(SessionHash.withdrawal(p));
    }

    function revokeDigest(bytes32 id, uint256 expectedEpoch, uint256 nonce, uint48 deadline)
        public
        view
        override
        returns (bytes32)
    {
        return _digest(keccak256(abi.encode(SessionHash.REVOKE, id, expectedEpoch, nonce, deadline)));
    }

    function epochDigest(uint256 expectedEpoch, uint256 newEpoch, uint256 nonce, uint48 deadline)
        public
        view
        override
        returns (bytes32)
    {
        return _digest(keccak256(abi.encode(SessionHash.EPOCH, expectedEpoch, newEpoch, nonce, deadline)));
    }

    function sessionState(bytes32 id) external view override returns (SessionState memory) {
        return _sessions[id];
    }

    function sessionNonceUsed(bytes32 id, uint256 nonce) external view override returns (bool) {
        return _used(_sessionNonces[id], nonce);
    }

    function ownerNonceUsed(uint256 atEpoch, uint256 nonce) external view override returns (bool) {
        return _used(_ownerNonces[atEpoch], nonce);
    }

    /// @dev Full policy hash is the ID; replayed registration never resets counters or tombstones.
    function registerSession(Grant calldata g, bytes calldata signature)
        external
        override
        nonReentrant
        returns (bytes32 id)
    {
        if (g.epoch != epoch) revert WrongEpoch();
        if (
            g.signer == address(0) || g.signer == owner || g.signer.code.length != 0 || g.validUntil <= g.validAfter
                || uint256(g.validUntil) - g.validAfter > MAX_SESSION_DURATION || g.validUntil < block.timestamp
                || g.underlyings.length > MAX_UNDERLYINGS || g.strategies == 0
                || (g.strategies & ~SESSION_STRATEGIES) != 0 || (g.maxOpens == 0 && g.maxCloses == 0)
                || g.maxFeePerTrade > g.maxFees
        ) revert InvalidGrant();
        if (g.maxOpens == 0) {
            if (g.maxAmountPerOpen != 0 || g.maxAmount != 0) revert InvalidGrant();
        } else if (g.maxAmountPerOpen == 0 || g.maxAmountPerOpen > g.maxAmount) {
            revert InvalidGrant();
        }
        for (uint256 n; n < g.underlyings.length; ++n) {
            if (g.underlyings[n] == 0 || (n != 0 && g.underlyings[n] <= g.underlyings[n - 1])) {
                revert InvalidGrant();
            }
        }
        id = SessionHash.grant(g);
        SessionState storage state = _sessions[id];
        if (state.revoked) revert SessionUnavailable();
        bytes32 previous = _grantNonces[epoch][g.nonce];
        if (previous != bytes32(0) && previous != id) revert GrantNonceUsed();
        // Installed policy remains valid independently of later ERC1271 policy changes.
        if (state.installed) return id;
        _verifyOwner(_digest(id), signature);
        // Installation never depends on funding. A directly funded account is
        // activated by its first sponsored open (see `_activate`).
        _grantNonces[epoch][g.nonce] = id;
        state.installed = true;
        emit SessionRegistered(id, g.signer, g);
    }

    function openWithSession(Grant calldata g, Intent calldata i, Open calldata p, bytes calldata signature)
        external
        payable
        override
        nonReentrant
        returns (bytes32 key)
    {
        bytes32 digest = openDigest(i, p);
        SessionState storage state = _consume(g, i, digest, signature);
        if (p.length != 2 || p.amountIn == 0 || p.amountIn > g.maxAmountPerOpen) revert PolicyViolation();
        // Reject unused nonzero legs rather than signing ambiguous parameters the core ignores.
        for (uint256 n = 2; n < 4; ++n) {
            if (p.isBuys[n] || p.isCalls[n] || p.optionIds[n] != bytes32(0)) revert PolicyViolation();
        }
        ITradingAccountFactory factory = _activate();
        (, uint256 tokenId,) = IController(factory.CONTROLLER())
            .validateOpenPosition(p.underlyingAssetIndex, p.length, p.isBuys, p.optionIds, p.isCalls);
        _validateToken(g, p.underlyingAssetIndex, tokenId);
        if (state.opens >= g.maxOpens || p.amountIn > g.maxAmount - state.amountSpent) revert BudgetExceeded();
        ++state.opens;
        state.amountSpent += p.amountIn;
        key = _openPosition(
            p.underlyingAssetIndex,
            p.length,
            p.isBuys,
            p.optionIds,
            p.isCalls,
            p.minSize,
            _usdcPath(),
            p.amountIn,
            0,
            i.source
        );
        emit SessionRequest(i.sessionId, i.nonce, digest, key, true, msg.value);
    }

    function closeWithSession(Grant calldata g, Intent calldata i, Close calldata p, bytes calldata signature)
        external
        payable
        override
        nonReentrant
        returns (bytes32 key)
    {
        bytes32 digest = closeDigest(i, p);
        SessionState storage state = _consume(g, i, digest, signature);
        _validateToken(g, p.underlyingAssetIndex, p.optionTokenId);
        address token = IOptionsMarketLookup(_factory().OPTIONS_MARKET()).getOptionsTokenByIndex(p.underlyingAssetIndex);
        if (p.size == 0 || token == address(0) || IERC1155(token).balanceOf(address(this), p.optionTokenId) < p.size) {
            revert PolicyViolation();
        }
        if (state.closes >= g.maxCloses) revert BudgetExceeded();
        ++state.closes;
        key = _closePosition(p.underlyingAssetIndex, p.optionTokenId, p.size, _usdcPath(), p.minAmountOut, 0, i.source);
        emit SessionRequest(i.sessionId, i.nonce, digest, key, false, msg.value);
    }

    function _consume(Grant calldata g, Intent calldata i, bytes32 digest, bytes calldata signature)
        private
        returns (SessionState storage state)
    {
        if (g.epoch != epoch || i.epoch != epoch) revert WrongEpoch();
        if (block.timestamp < g.validAfter || block.timestamp > g.validUntil || block.timestamp > i.deadline) {
            revert AuthorizationExpired();
        }
        if (i.sessionId != SessionHash.grant(g)) revert InvalidGrant();
        state = _sessions[i.sessionId];
        if (!state.installed || state.revoked) revert SessionUnavailable();
        (address signer, ECDSA.RecoverError error) = ECDSA.tryRecover(digest, signature);
        if (error != ECDSA.RecoverError.NoError || signer != g.signer) revert InvalidSignature();
        // The core requires msg.value to equal its current execution fee; the grant bounds it.
        if (msg.value > g.maxFeePerTrade) revert InvalidExecutionFee();
        if (msg.value > g.maxFees - state.feesSpent) revert BudgetExceeded();
        _use(_sessionNonces[i.sessionId], i.nonce);
        state.feesSpent += msg.value;
    }

    /// @dev Registers a created, directly funded account on its first sponsored open. The owner's
    ///      installed grant is the consent; the gas payer has no account privilege and cannot choose
    ///      the token, owner or funds. Safe mode and the sub-account limit still apply here.
    function _activate() private returns (ITradingAccountFactory factory) {
        factory = _factory();
        if (!factory.isAccount(address(this))) {
            _settleExternalDelta(factory.USDC(), 0);
            factory.onAccountFunded();
        }
    }

    function _validateToken(Grant calldata g, uint16 asset, uint256 tokenId) private view {
        bool permitted = g.underlyings.length == 0; // an empty list permits every asset
        for (uint256 n; n < g.underlyings.length; ++n) {
            if (g.underlyings[n] == asset) permitted = true;
        }
        uint8 strategy = uint8((tokenId >> 196) & 0xf);
        if (
            !permitted || uint16(tokenId >> 240) != asset || strategy < 5 || strategy > 8
                || (g.strategies & (uint16(1) << strategy)) == 0
        ) revert PolicyViolation();
        if (uint40(tokenId >> 200) <= block.timestamp || !SessionPolicy.canonicalSpread(tokenId)) {
            revert PolicyViolation();
        }
    }

    function _usdcPath() private view returns (address[] memory path) {
        address usdc = _factory().USDC();
        if (IOptionsMarketLookup(_factory().OPTIONS_MARKET()).mainStableAsset() != usdc) revert InvalidPath();
        path = new address[](1);
        path[0] = usdc;
    }

    function revokeSession(bytes32 id) external override onlyOwner nonReentrant {
        _revoke(id);
    }

    function revokeSessionBySignature(
        bytes32 id,
        uint256 expectedEpoch,
        uint256 nonce,
        uint48 deadline,
        bytes calldata signature
    ) external override nonReentrant {
        _ownerAuthorization(expectedEpoch, nonce, deadline, revokeDigest(id, expectedEpoch, nonce, deadline), signature);
        _revoke(id);
    }

    function _revoke(bytes32 id) private {
        _sessions[id].revoked = true; // also blocks a signed grant that has not yet been installed
        emit SessionRevoked(id);
    }

    function invalidateEpoch(uint256 expectedEpoch, uint256 newEpoch) external override onlyOwner nonReentrant {
        _invalidateEpoch(expectedEpoch, newEpoch);
    }

    function invalidateEpochBySignature(
        uint256 expectedEpoch,
        uint256 newEpoch,
        uint256 nonce,
        uint48 deadline,
        bytes calldata signature
    ) external override nonReentrant {
        _ownerAuthorization(
            expectedEpoch, nonce, deadline, epochDigest(expectedEpoch, newEpoch, nonce, deadline), signature
        );
        _invalidateEpoch(expectedEpoch, newEpoch);
    }

    function _invalidateEpoch(uint256 expectedEpoch, uint256 newEpoch) private {
        // A routine revoke-all increments once; a malformed UI/relay value cannot jump to max.
        if (epoch != expectedEpoch || expectedEpoch == type(uint256).max || newEpoch != expectedEpoch + 1) {
            revert WrongEpoch();
        }
        epoch = newEpoch;
        emit EpochInvalidated(expectedEpoch, newEpoch);
    }

    /// @dev Fresh owner authority only. No fee deduction, arbitrary target call or session shortcut.
    function withdrawBySignature(Withdrawal calldata p, bytes calldata signature) external override nonReentrant {
        _ownerAuthorization(p.epoch, p.nonce, p.deadline, withdrawalDigest(p), signature);
        if (p.kind == 0 && p.id == 0 && p.token != address(0)) {
            _withdrawToken(p.token, p.amount, p.to);
        } else if (p.kind == 1 && p.id == 0 && p.token == address(0)) {
            _withdrawNative(p.amount, payable(p.to));
        } else if (p.kind == 2 && p.token != address(0)) {
            _withdrawERC1155(p.token, p.id, p.amount, p.to);
        } else {
            revert InvalidWithdrawal();
        }
    }

    function _ownerAuthorization(
        uint256 expectedEpoch,
        uint256 nonce,
        uint48 deadline,
        bytes32 digest,
        bytes calldata signature
    ) private {
        if (expectedEpoch != epoch) revert WrongEpoch();
        if (block.timestamp > deadline) revert AuthorizationExpired();
        _verifyOwner(digest, signature);
        _use(_ownerNonces[epoch], nonce);
        emit OwnerAuthorizationUsed(epoch, nonce, digest);
    }

    function _verifyOwner(bytes32 digest, bytes calldata signature) private view {
        if (!SignatureChecker.isValidSignatureNow(owner, digest, signature)) revert InvalidSignature();
    }

    function _used(mapping(uint256 => uint256) storage bitmap, uint256 nonce) private view returns (bool) {
        return (bitmap[nonce >> 8] & (uint256(1) << uint8(nonce))) != 0;
    }

    function _use(mapping(uint256 => uint256) storage bitmap, uint256 nonce) private {
        uint256 mask = uint256(1) << uint8(nonce);
        if ((bitmap[nonce >> 8] & mask) != 0) revert NonceUsed();
        bitmap[nonce >> 8] |= mask;
    }
}
