// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IPositionValueFeed {
    function description() external view returns (string memory);

    function setUpdateDuration(uint256 _updateDuration) external;

    function feedPV(address[] memory _vaults, uint256[] memory _pv, bool[] memory _isPvNegative, uint256 _positionKeysStart, uint256 _deadline) external;
    function getPVAndSign(address _vault) external view returns (uint256, bool);
    function getPVAndSignWithLastUpdatedAt(address _vault) external view returns (uint256, bool, uint256);
    function getPVLastUpdatedAt() external view returns (uint256);

    function feedAPV(address[] memory _vaults, uint256[] memory _apv, uint256 _positionKeysStart, uint256 _deadline) external;
    function getAPV(address _vault) external view returns (uint256);
    function getAPVWithLastUpdatedAt(address _vault) external view returns (uint256, uint256);
    function getAPVLastUpdatedAt() external view returns (uint256);
}