// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @title ITradingAccountFactory
/// @notice Non-upgradeable factory + registry + fixed-address event hub for trading accounts.
interface ITradingAccountFactory {
    struct CoreAddresses {
        address usdc;
        address positionManager;
        address settleManager;
        address controller;
        address referral;
        address optionsMarket;
    }

    struct AccountInfo {
        address owner;
        uint96 subIndex;
    }

    // ---- errors ----
    error ZeroAddress();
    error ZeroAmount();
    error NotAdmin();
    error NotPendingAdmin();
    error NotGuardianOrAdmin();
    error NotOwner();
    error NotAccount(address caller);
    error NotCreated(address account);
    error NotFunded(address account);
    error SafeModeActive();
    error SubAccountLimit(address owner, uint96 limit);
    error Create2Mismatch(address expected, address actual);
    error ImplementationFactoryMismatch(address implementationFactory);
    error InvalidLimit();

    // ---- account lifecycle events ----
    event AccountCreated(address indexed owner, uint96 indexed subIndex, address indexed account);
    event AccountRegistered(address indexed owner, uint96 indexed subIndex, address indexed account);

    // ---- hub events (account = clone address, always indexed) ----
    event Deposited(address indexed account, address indexed token, uint256 amount, address indexed from);
    event Withdrawn(address indexed account, address indexed token, uint256 amount, address indexed to);
    event PositionWithdrawn(address indexed account, address indexed token, uint256 id, uint256 amount, address indexed to);
    event ExternalDeposit(address indexed account, address indexed token, uint256 amount);
    event ReferralSynced(address indexed account, address indexed parent);
    /// @notice (M3) Entry-path tag for a core request. `source` is caller-supplied metadata for
    ///         display / points only and must never gate an on-chain benefit (plan §4.5).
    event RequestTagged(address indexed account, bytes32 indexed requestKey, bool isOpen, uint8 source);

    // ---- admin events ----
    event AllowlistChanged(address indexed account, bool enabled);
    event OpenToAllChanged(bool enabled);
    event SafeModeChanged(bool enabled);
    event MaxSubAccountsChanged(uint96 maxSubAccounts);
    event AdminTransferStarted(address indexed pendingAdmin);
    event AdminTransferred(address indexed admin);
    event GuardianChanged(address indexed guardian);
    event BeaconUpgraded(address indexed implementation);
    event BeaconOwnershipTransferred(address indexed newOwner);

    // ---- beacon governance (factory owns the beacon; admin drives upgrades through the factory) ----
    function upgradeBeacon(address newImplementation) external;
    function transferBeaconOwnership(address newOwner) external;

    // ---- immutable config ----
    function BEACON() external view returns (address);
    function INITCODE_HASH() external view returns (bytes32);
    function USDC() external view returns (address);
    function POSITION_MANAGER() external view returns (address);
    function SETTLE_MANAGER() external view returns (address);
    function CONTROLLER() external view returns (address);
    function REFERRAL() external view returns (address);
    function OPTIONS_MARKET() external view returns (address);

    // ---- creation ----
    function createAccount(address owner, uint96 subIndex) external returns (address account);
    function createAccountAndDeposit(address owner, uint96 subIndex, uint256 amount) external returns (address account);
    function createAccountAndDepositWithPermit(
        address owner,
        uint96 subIndex,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (address account);
    function registerAccount(uint96 subIndex) external returns (address account);

    // ---- registry views ----
    function computeAddress(address owner, uint96 subIndex) external view returns (address);
    function isCreated(address account) external view returns (bool);
    function isAccount(address account) external view returns (bool);
    function accountInfo(address account) external view returns (address owner, uint96 subIndex);
    function accountOf(address owner, uint96 subIndex) external view returns (address);
    function accountsOf(address owner) external view returns (address[] memory);
    function accountCount() external view returns (uint256);
    function accounts(uint256 offset, uint256 limit) external view returns (address[] memory page);

    // ---- policy views ----
    function safeMode() external view returns (bool);
    function maxSubAccounts() external view returns (uint96);
    function isOpenAllowed(address account) external view returns (bool);
    function canOpen(address account) external view returns (bool);

    // ---- event hub (created accounts only) ----
    function onDeposited(address token, uint256 amount, address from) external;
    function onAccountFunded() external;
    function onWithdrawn(address token, uint256 amount, address to) external;
    function onPositionWithdrawn(address token, uint256 id, uint256 amount, address to) external;
    function onExternalDeposit(address token, uint256 amount) external;
    function onReferralSynced(address parent) external;
    function onRequestTagged(bytes32 requestKey, bool isOpen, uint8 source) external;
}
