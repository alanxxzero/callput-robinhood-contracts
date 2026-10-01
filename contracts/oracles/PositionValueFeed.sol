// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IPositionValueFeed.sol";
import "../interfaces/IPositionManager.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../AuthorityUtil.sol";

contract PositionValueFeed is IPositionValueFeed, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant MAX_UPDATE_DURATION = 90 minutes; // 1800 (G: 30 minutes = 1800 seconds)

    string public override description;
    
    uint256 public pvLastUpdatedAt;
    uint256 public apvLastUpdatedAt;
    uint256 public updateDuration; // 300 = 5 minute (G: 300 = 5 minutes)

    mapping (address => uint256) public pv; // vault => Position Value
    mapping (address => bool) public isPvNegative; // vault => whether pv is negative

    mapping (address => uint256) public apv; // vault => Absolute Position Value
    
    address public positionManager;
    uint256 public lastPvPositionKeysStart; // Last PV position keys start index
    uint256 public lastApvPositionKeysStart; // Last APV position keys start index

    event SetPositionManager(address indexed positionManager);
    event FeedPV(address indexed vault, uint256 pv, bool isPvNegative, address updater);
    event FeedAPV(address indexed vault, uint256 apv, address updater);

    function initialize(
        address _positionManager,
        IOptionsAuthority _authority
    ) public initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        description = "PositionValueFeed";
        updateDuration = 300; // should not be more than MAX_UPDATE_DURATION

        positionManager = _positionManager;
        lastPvPositionKeysStart = IPositionManager(positionManager).positionRequestKeysStart();
        lastApvPositionKeysStart = IPositionManager(positionManager).positionRequestKeysStart();
    }

    function setUpdateDuration(uint256 _updateDuration) external override onlyAdmin {
        require(_updateDuration <= MAX_UPDATE_DURATION, "PositionValueFeed: invalid _updateDuration");
        updateDuration = _updateDuration;
    }

    function setPositionManager(address _positionManager) external onlyAdmin {
        require(_positionManager != address(0), "PositionValueFeed: invalid positionManager");
        positionManager = _positionManager;
        emit SetPositionManager(_positionManager);
    }

    function feedPV(
        address[] memory _vaults,
        uint256[] memory _pv,
        bool[] memory _isPvNegative,
        uint256 _positionKeysStart,
        uint256 _deadline
    ) external override onlyKeeper {
        require(_vaults.length == _pv.length && _vaults.length == _isPvNegative.length, "PositionValueFeed: Array lengths mismatch");
        require(block.timestamp <= _deadline, "PositionValueFeed: DEADLINE_EXPIRED");
        require(_positionKeysStart >= lastPvPositionKeysStart, "PositionValueFeed: invalid position keys start");

        lastPvPositionKeysStart = _positionKeysStart; // Update last PV position keys start
        pvLastUpdatedAt = block.timestamp;

        for (uint256 i = 0; i < _vaults.length;) {
            pv[_vaults[i]] = _pv[i];
            isPvNegative[_vaults[i]] = _isPvNegative[i];
            emit FeedPV(_vaults[i], _pv[i], _isPvNegative[i], msg.sender);
            unchecked { i++; }
        }
    }

    function getPVAndSign(address _vault) public override view returns (uint256, bool) {
        require(block.timestamp <= pvLastUpdatedAt + updateDuration, "PositionValueFeed: pv is not being updated");
        require(lastPvPositionKeysStart == IPositionManager(positionManager).positionRequestKeysStart(), "PositionValueFeed: position state mismatch");
        return (pv[_vault], isPvNegative[_vault]);
    }

    function getPVAndSignWithLastUpdatedAt(address _vault) external override view returns (uint256, bool, uint256) {
        (uint256 _pv, bool _isPvNegative) = getPVAndSign(_vault);
        return (_pv, _isPvNegative, pvLastUpdatedAt);
    }

    function getPVLastUpdatedAt() external override view returns (uint256) {
        return pvLastUpdatedAt;
    }

    // APV
    function feedAPV(
        address[] memory _vaults,
        uint256[] memory _apv,
        uint256 _positionKeysStart,
        uint256 _deadline
    ) external override onlyKeeper {
        require(_vaults.length == _apv.length, "PositionValueFeed: Array lengths mismatch");
        require(block.timestamp <= _deadline, "PositionValueFeed: DEADLINE_EXPIRED");
        require(_positionKeysStart >= lastApvPositionKeysStart, "PositionValueFeed: invalid position keys start");

        lastApvPositionKeysStart = _positionKeysStart; // Update last APV position keys start
        apvLastUpdatedAt = block.timestamp;

        for (uint256 i = 0; i < _vaults.length;) {
            apv[_vaults[i]] = _apv[i];
            emit FeedAPV(_vaults[i], _apv[i], msg.sender);
            unchecked { i++; }
        }
    }

    function getAPV(address _vault) public override view returns (uint256) {
        require(block.timestamp <= apvLastUpdatedAt + updateDuration, "PositionValueFeed: apv is not being updated");
        require(lastApvPositionKeysStart == IPositionManager(positionManager).positionRequestKeysStart(), "PositionValueFeed: position state mismatch");
        return apv[_vault];
    }

    function getAPVWithLastUpdatedAt(address _vault) external override view returns (uint256, uint256) {
        uint256 _apv = getAPV(_vault);
        return (_apv, apvLastUpdatedAt);
    }


    function getAPVLastUpdatedAt() external override view returns (uint256) {
        return apvLastUpdatedAt;
    }
}
