// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @notice Version 3 session extension. Legacy ITradingAccount selectors remain available.
interface ITradingAccountSessions {
    struct Grant {
        address signer;
        uint256 nonce;
        uint256 epoch;
        uint48 validAfter;
        uint48 validUntil;
        uint16[] underlyings;
        uint16 strategies;
        uint256 maxAmountPerOpen;
        uint256 maxAmount;
        uint32 maxOpens;
        uint32 maxCloses;
        uint256 maxFeePerTrade;
        uint256 maxFees;
    }

    struct Intent {
        bytes32 sessionId;
        uint256 epoch;
        uint256 nonce;
        uint48 deadline;
        uint8 source;
    }

    // Single USDC path and minOutWhenSwap=0 are protocol constants, not relay input.
    struct Open {
        uint16 underlyingAssetIndex;
        uint8 length;
        bool[4] isBuys;
        bytes32[4] optionIds;
        bool[4] isCalls;
        uint256 minSize;
        uint256 amountIn;
    }

    struct Close {
        uint16 underlyingAssetIndex;
        uint256 optionTokenId;
        uint256 size;
        uint256 minAmountOut;
    }

    struct Withdrawal {
        uint8 kind; // 0 ERC20, 1 native, 2 ERC1155 (including option positions)
        address token;
        uint256 id;
        uint256 amount;
        address to;
        uint256 epoch;
        uint256 nonce;
        uint48 deadline;
    }

    struct SessionState {
        bool installed;
        bool revoked;
        uint32 opens;
        uint32 closes;
        uint256 amountSpent;
        uint256 feesSpent;
    }

    error InvalidGrant();
    error InvalidSignature();
    error WrongEpoch();
    error AuthorizationExpired();
    error SessionUnavailable();
    error GrantNonceUsed();
    error NonceUsed();
    error PolicyViolation();
    error BudgetExceeded();
    error InvalidExecutionFee();
    error InvalidWithdrawal();
    error InvalidFundingDelta();

    event SessionRegistered(bytes32 indexed sessionId, address indexed signer, Grant grant);
    event SessionRevoked(bytes32 indexed sessionId);
    event EpochInvalidated(uint256 previousEpoch, uint256 newEpoch);
    event SessionRequest(
        bytes32 indexed sessionId,
        uint256 indexed nonce,
        bytes32 indexed digest,
        bytes32 requestKey,
        bool isOpen,
        uint256 executionFee
    );
    event OwnerAuthorizationUsed(uint256 indexed epoch, uint256 indexed nonce, bytes32 indexed digest);
    function domainSeparator() external view returns (bytes32);
    function depositWithAuthorization(
        uint256 amount, uint256 validAfter, uint256 validBefore, bytes32 nonce, bytes calldata ownerSignature
    ) external;
    function hashGrant(Grant calldata grant) external pure returns (bytes32);
    function grantDigest(Grant calldata grant) external view returns (bytes32);
    function openDigest(Intent calldata intent, Open calldata params) external view returns (bytes32);
    function closeDigest(Intent calldata intent, Close calldata params) external view returns (bytes32);
    function withdrawalDigest(Withdrawal calldata params) external view returns (bytes32);
    function revokeDigest(bytes32 sessionId, uint256 expectedEpoch, uint256 nonce, uint48 deadline)
        external
        view
        returns (bytes32);
    function epochDigest(uint256 expectedEpoch, uint256 newEpoch, uint256 nonce, uint48 deadline)
        external
        view
        returns (bytes32);

    function sessionState(bytes32 sessionId) external view returns (SessionState memory);
    function sessionNonceUsed(bytes32 sessionId, uint256 nonce) external view returns (bool);
    function ownerNonceUsed(uint256 atEpoch, uint256 nonce) external view returns (bool);
    function registerSession(Grant calldata grant, bytes calldata ownerSignature) external returns (bytes32);
    function openWithSession(
        Grant calldata grant,
        Intent calldata intent,
        Open calldata params,
        bytes calldata signature
    ) external payable returns (bytes32);
    function closeWithSession(
        Grant calldata grant,
        Intent calldata intent,
        Close calldata params,
        bytes calldata signature
    ) external payable returns (bytes32);

    function revokeSession(bytes32 sessionId) external;
    function revokeSessionBySignature(
        bytes32 sessionId,
        uint256 expectedEpoch,
        uint256 nonce,
        uint48 deadline,
        bytes calldata signature
    ) external;
    function invalidateEpoch(uint256 expectedEpoch, uint256 newEpoch) external;
    function invalidateEpochBySignature(
        uint256 expectedEpoch,
        uint256 newEpoch,
        uint256 nonce,
        uint48 deadline,
        bytes calldata signature
    ) external;
    function withdrawBySignature(Withdrawal calldata params, bytes calldata signature) external;
}
