// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title ITradingAccount
/// @notice Per-user trading account (beacon proxy clone).
///         v1 = deposit / withdraw. v2 adds the self-funded trading path (open / close / settle).
interface ITradingAccount {
    // ---- errors ----
    error NotOwner();
    error NotFactory();
    error ZeroAddress();
    error ZeroAmount();
    error Reentrancy();
    error NativeTransferFailed();
    error UnknownOptionsToken(uint256 tokenId);
    error UseWithdrawNative();
    // ---- v2 ----
    error OpenNotAllowed();
    error InvalidPath();

    // ---- views ----
    function FACTORY() external view returns (address);
    function owner() external view returns (address);
    function subIndex() external view returns (uint96);
    function epoch() external view returns (uint256);
    function balanceCheckpoint(address token) external view returns (uint256);
    function version() external pure returns (uint256);

    // ---- lifecycle (factory only) ----
    function initialize(address owner_, uint96 subIndex_) external;
    function syncCheckpoint(address token, uint256 amountJustReceived) external;

    // ---- deposits (owner only, blocked by safe-mode) ----
    function deposit(uint256 amount) external;
    function depositWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    // ---- withdrawals (owner only, never pausable) ----
    function withdraw(address token, uint256 amount, address to) external;
    function withdrawNative(uint256 amount, address payable to) external;
    function withdrawPosition(uint256 tokenId, uint256 amount, address to) external;
    function withdrawERC1155(address token, uint256 id, uint256 amount, address to) external;

    // ---- trading (v2) ----
    /// @dev owner only; `msg.value` = core execution fee. `leadTrader` is fixed to address(0) (F1).
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
    ) external payable returns (bytes32 requestKey);

    /// @dev owner only; not gated by safe-mode / allowlist — closing must always stay open.
    function closePosition(
        uint16 underlyingAssetIndex,
        uint256 optionTokenId,
        uint256 size,
        address[] calldata path,
        uint256 minAmountOut,
        uint256 minOutWhenSwap,
        uint8 source
    ) external payable returns (bytes32 requestKey);

    /// @dev permissionless; every core argument is derived on-chain and the payout goes to this
    ///      account (F6). All-or-nothing: reverts unless every listed lot settles; an empty list
    ///      reverts with ZeroAmount (v6).
    function settleExpired(uint256[] calldata optionTokenIds)
        external
        returns (uint256[] memory amountsOut, bool[] memory settled);

    // ---- referral (owner only; existing Referral enforces one-time registration) ----
    function setReferral(address parent) external;

    // ---- permissionless helpers ----
    function recordExternalDeposit(address token) external returns (uint256 delta);
}
