// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITradingAccount} from "./interfaces/ITradingAccount.sol";
import {ITradingAccountFactory} from "./interfaces/ITradingAccountFactory.sol";

/// @title TradingAccountFactory
/// @notice Non-upgradeable. Deploys `TradingAccount` beacon proxies at CREATE2 addresses derived from
///         `(owner, subIndex)`, keeps the registry of funded accounts, holds protocol-wide policy
///         (safe-mode, open allowlist, sub-account cap) and acts as the fixed-address event hub
///         through which every account emits its events (plan §4.1).
/// @dev Invariants
///      - F4: creation is permissionless (address is owner-derived; a third-party deploy is harmless),
///        the registry admits an account only once the owner funds it.
///      - F5: BeaconProxy constructor data is fixed to `(BEACON, "")` so the initcode hash is constant;
///        `initialize` runs in the same transaction as the deploy.
///      - Core addresses live here as immutables; the account implementation only knows `FACTORY`.
///      - Nothing in this contract can block a withdrawal: `onWithdrawn`/`onPositionWithdrawn` only
///        check that the caller is a factory-created clone and emit.
contract TradingAccountFactory is ITradingAccountFactory {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------
    // immutable config
    // ------------------------------------------------------------------

    address public immutable override BEACON;
    bytes32 public immutable override INITCODE_HASH;
    address public immutable override USDC;
    address public immutable override POSITION_MANAGER;
    address public immutable override SETTLE_MANAGER;
    address public immutable override CONTROLLER;
    address public immutable override REFERRAL;
    address public immutable override OPTIONS_MARKET;

    // ------------------------------------------------------------------
    // policy / roles
    // ------------------------------------------------------------------

    address public admin;
    address public pendingAdmin;
    /// @notice May only enable safe-mode (emergency brake). Disabling is admin-only.
    address public guardian;
    bool public override safeMode;
    uint96 public override maxSubAccounts;

    // ------------------------------------------------------------------
    // registry
    // ------------------------------------------------------------------

    mapping(address => AccountInfo) private _info; // created clones (owner != 0)
    mapping(address => bool) public override isAccount; // registered (funded) clones
    mapping(address => mapping(uint96 => address)) private _accountOf;
    mapping(address => address[]) private _accountsOf;
    address[] private _accounts;
    mapping(address => bool) private _isOpenAllowed;
    /// @notice Explicit public admission. Defaults to the restricted rollout policy.
    bool public openToAll;

    // ------------------------------------------------------------------
    // modifiers
    // ------------------------------------------------------------------

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyCreatedAccount() {
        if (_info[msg.sender].owner == address(0)) revert NotAccount(msg.sender);
        _;
    }

    // ------------------------------------------------------------------
    // constructor
    // ------------------------------------------------------------------

    /// @param beacon_ UpgradeableBeacon whose implementation must have `FACTORY == address(this)`.
    /// @param core_ Core protocol addresses (all non-zero).
    /// @param admin_ Policy admin (Safe multisig).
    /// @param maxSubAccounts_ Per-owner cap on registered accounts (must be > 0).
    constructor(address beacon_, CoreAddresses memory core_, address admin_, uint96 maxSubAccounts_) {
        if (
            beacon_ == address(0) || core_.usdc == address(0) || core_.positionManager == address(0) ||
            core_.settleManager == address(0) || core_.controller == address(0) || core_.referral == address(0) ||
            core_.optionsMarket == address(0) || admin_ == address(0)
        ) revert ZeroAddress();
        if (maxSubAccounts_ == 0) revert InvalidLimit();

        // The implementation is compiled with this factory's address as an immutable; refuse to wire up
        // a beacon that points anywhere else (guards against a wrong deploy order / predicted address).
        address impl = IBeacon(beacon_).implementation();
        address implFactory = ITradingAccount(impl).FACTORY();
        if (implFactory != address(this)) revert ImplementationFactoryMismatch(implFactory);

        BEACON = beacon_;
        INITCODE_HASH = keccak256(abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(beacon_, bytes(""))));
        USDC = core_.usdc;
        POSITION_MANAGER = core_.positionManager;
        SETTLE_MANAGER = core_.settleManager;
        CONTROLLER = core_.controller;
        REFERRAL = core_.referral;
        OPTIONS_MARKET = core_.optionsMarket;

        admin = admin_;
        maxSubAccounts = maxSubAccounts_;
        emit AdminTransferred(admin_);
        emit MaxSubAccountsChanged(maxSubAccounts_);
    }

    // ------------------------------------------------------------------
    // creation
    // ------------------------------------------------------------------

    /// @notice Deploys (if needed) the account for `(owner, subIndex)`. Permissionless and idempotent.
    ///         Does NOT register the account; registration happens on the owner's first deposit.
    function createAccount(address owner, uint96 subIndex) public override returns (address account) {
        if (owner == address(0)) revert ZeroAddress();
        bytes32 salt = _salt(owner, subIndex);
        account = Create2.computeAddress(salt, INITCODE_HASH);
        if (_info[account].owner != address(0)) return account;

        address deployed = address(new BeaconProxy{salt: salt}(BEACON, ""));
        if (deployed != account) revert Create2Mismatch(account, deployed);

        _info[account] = AccountInfo({owner: owner, subIndex: subIndex});
        ITradingAccount(account).initialize(owner, subIndex);
        emit AccountCreated(owner, subIndex, account);
    }

    /// @notice Create (if needed), register and fund in one transaction. Caller must be `owner` and must
    ///         have approved this factory as USDC spender.
    function createAccountAndDeposit(address owner, uint96 subIndex, uint256 amount)
        external
        override
        returns (address account)
    {
        return _createAndDeposit(owner, subIndex, amount);
    }

    /// @notice Same as `createAccountAndDeposit` with an EIP-2612 permit. A front-run or already-consumed
    ///         permit is tolerated: the transfer then relies on the existing allowance.
    function createAccountAndDepositWithPermit(
        address owner,
        uint96 subIndex,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override returns (address account) {
        // solhint-disable-next-line no-empty-blocks
        try IERC20Permit(USDC).permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
        return _createAndDeposit(owner, subIndex, amount);
    }

    /// @notice Registers an already-created, externally funded account (direct transfer / CCTP mint
    ///         before any `deposit()`). Owner only; requires a non-zero USDC balance.
    function registerAccount(uint96 subIndex) external override returns (address account) {
        account = Create2.computeAddress(_salt(msg.sender, subIndex), INITCODE_HASH);
        if (_info[account].owner == address(0)) revert NotCreated(account);
        if (IERC20(USDC).balanceOf(account) == 0) revert NotFunded(account);
        _register(msg.sender, subIndex, account);
    }

    function _createAndDeposit(address owner, uint96 subIndex, uint256 amount) internal returns (address account) {
        if (msg.sender != owner) revert NotOwner();
        if (amount == 0) revert ZeroAmount();
        if (safeMode) revert SafeModeActive();

        account = createAccount(owner, subIndex);
        _register(owner, subIndex, account);

        IERC20(USDC).safeTransferFrom(msg.sender, account, amount);
        ITradingAccount(account).syncCheckpoint(USDC, amount);
        emit Deposited(account, USDC, amount, msg.sender);
    }

    function _register(address owner, uint96 subIndex, address account) internal {
        if (isAccount[account]) return;
        address[] storage list = _accountsOf[owner];
        uint96 limit = maxSubAccounts;
        if (list.length >= limit) revert SubAccountLimit(owner, limit);

        isAccount[account] = true;
        _accountOf[owner][subIndex] = account;
        list.push(account);
        _accounts.push(account);
        emit AccountRegistered(owner, subIndex, account);
    }

    function _salt(address owner, uint96 subIndex) internal pure returns (bytes32) {
        return keccak256(abi.encode(owner, subIndex));
    }

    // ------------------------------------------------------------------
    // event hub (callable by factory-created clones only)
    // ------------------------------------------------------------------

    /// @dev Deposit entry point. Blocked by safe-mode; registers the account on first call.
    function onDeposited(address token, uint256 amount, address from) external override onlyCreatedAccount {
        if (safeMode) revert SafeModeActive();
        AccountInfo memory info = _info[msg.sender];
        _register(info.owner, info.subIndex, msg.sender);
        emit Deposited(msg.sender, token, amount, from);
    }

    /// @notice A created account activates after verifying its owner's session grant.
    /// @dev Direct transfers already changed its ERC20 balance; this emits only registration.
    function onAccountFunded() external override onlyCreatedAccount {
        if (safeMode) revert SafeModeActive();
        if (IERC20(USDC).balanceOf(msg.sender) == 0) revert NotFunded(msg.sender);
        AccountInfo memory info = _info[msg.sender];
        _register(info.owner, info.subIndex, msg.sender);
    }

    /// @dev Never gated: withdrawals must succeed under every policy state.
    function onWithdrawn(address token, uint256 amount, address to) external override onlyCreatedAccount {
        emit Withdrawn(msg.sender, token, amount, to);
    }

    /// @dev Never gated.
    function onPositionWithdrawn(address token, uint256 id, uint256 amount, address to)
        external
        override
        onlyCreatedAccount
    {
        emit PositionWithdrawn(msg.sender, token, id, amount, to);
    }

    function onExternalDeposit(address token, uint256 amount) external override onlyCreatedAccount {
        emit ExternalDeposit(msg.sender, token, amount);
    }

    function onReferralSynced(address parent) external override onlyCreatedAccount {
        emit ReferralSynced(msg.sender, parent);
    }

    /// @dev (M3) Tags a core request with the entry path it came from. Never gated: a tag must not be
    ///      able to make a trade fail. `source` is not validated on-chain — it is display / points
    ///      metadata that the caller controls, so no on-chain benefit may depend on it (plan §4.5).
    function onRequestTagged(bytes32 requestKey, bool isOpen, uint8 source) external override onlyCreatedAccount {
        emit RequestTagged(msg.sender, requestKey, isOpen, source);
    }

    // ------------------------------------------------------------------
    // registry views
    // ------------------------------------------------------------------

    function computeAddress(address owner, uint96 subIndex) external view override returns (address) {
        return Create2.computeAddress(_salt(owner, subIndex), INITCODE_HASH);
    }

    function isCreated(address account) external view override returns (bool) {
        return _info[account].owner != address(0);
    }

    function accountInfo(address account) external view override returns (address owner, uint96 subIndex) {
        AccountInfo memory info = _info[account];
        return (info.owner, info.subIndex);
    }

    /// @return The registered account for `(owner, subIndex)`, or zero if not registered.
    function accountOf(address owner, uint96 subIndex) external view override returns (address) {
        return _accountOf[owner][subIndex];
    }

    /// @return Registered accounts of `owner` (bounded by `maxSubAccounts`).
    function accountsOf(address owner) external view override returns (address[] memory) {
        return _accountsOf[owner];
    }

    function accountCount() external view override returns (uint256) {
        return _accounts.length;
    }

    /// @notice Paginated view over all registered accounts in registration order.
    function accounts(uint256 offset, uint256 limit) external view override returns (address[] memory page) {
        uint256 total = _accounts.length;
        if (offset >= total) return page;
        uint256 remaining = total - offset;
        uint256 end = limit >= remaining ? total : offset + limit;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; ) {
            page[i - offset] = _accounts[i];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Gate that the M3 trading path will check before every open.
    function canOpen(address account) external view override returns (bool) {
        return !safeMode && isAccount[account] && isOpenAllowed(account);
    }

    function isOpenAllowed(address account) public view override returns (bool) {
        return openToAll || _isOpenAllowed[account];
    }

    /// @notice Public admission never bypasses registration, safe mode or owner permissions.
    function setOpenToAll(bool enabled) external onlyAdmin {
        openToAll = enabled;
        emit OpenToAllChanged(enabled);
    }

    // ------------------------------------------------------------------
    // admin
    // ------------------------------------------------------------------

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(newAdmin);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferred(msg.sender);
    }

    function setGuardian(address newGuardian) external onlyAdmin {
        guardian = newGuardian;
        emit GuardianChanged(newGuardian);
    }

    /// @notice Safe-mode blocks `deposit()` entry points and (from M3) new opens. It never blocks
    ///         withdrawals or account creation. Guardian may enable only; admin may enable or disable.
    function setSafeMode(bool enabled) external {
        if (msg.sender != admin && !(enabled && msg.sender == guardian)) {
            revert NotGuardianOrAdmin();
        }
        safeMode = enabled;
        emit SafeModeChanged(enabled);
    }

    function setMaxSubAccounts(uint96 newMax) external onlyAdmin {
        if (newMax == 0) revert InvalidLimit();
        maxSubAccounts = newMax;
        emit MaxSubAccountsChanged(newMax);
    }

    // ------------------------------------------------------------------
    // beacon governance — the factory owns the beacon so no implementation whose FACTORY is not this
    // contract can ever be installed (a wrong FACTORY would make every hub call, i.e. every withdrawal, revert)
    // ------------------------------------------------------------------

    /// @notice Upgrade every account to `newImplementation` after verifying it was compiled for this factory.
    ///         F7 still applies: no stateful reinitializer, new fields must be zero-safe.
    function upgradeBeacon(address newImplementation) external override onlyAdmin {
        if (newImplementation == address(0)) revert ZeroAddress();
        address implFactory = ITradingAccount(newImplementation).FACTORY();
        if (implFactory != address(this)) revert ImplementationFactoryMismatch(implFactory);
        UpgradeableBeacon(BEACON).upgradeTo(newImplementation);
        emit BeaconUpgraded(newImplementation);
    }

    /// @notice Explicit escape hatch (e.g. moving beacon control to a timelock or a successor factory).
    ///         Deliberate admin action only; ordinary upgrades must go through `upgradeBeacon`.
    function transferBeaconOwnership(address newOwner) external override onlyAdmin {
        if (newOwner == address(0)) revert ZeroAddress();
        UpgradeableBeacon(BEACON).transferOwnership(newOwner);
        emit BeaconOwnershipTransferred(newOwner);
    }

    /// @notice Account-level open allowlist (pre-audit exposure control). Storage only in v1; the M3
    ///         trading path checks it via `canOpen`.
    function setOpenAllowlist(address[] calldata accountList, bool enabled) external onlyAdmin {
        for (uint256 i = 0; i < accountList.length; ) {
            _isOpenAllowed[accountList[i]] = enabled;
            emit AllowlistChanged(accountList[i], enabled);
            unchecked {
                ++i;
            }
        }
    }
}
