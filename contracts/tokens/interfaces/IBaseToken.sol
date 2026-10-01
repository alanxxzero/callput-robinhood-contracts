// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IBaseToken {
    function totalStaked() external view returns (uint256);
    function stakedBalance(address _account) external view returns (uint256);
    function setInPrivateTransferMode(bool _inPrivateTransferMode) external;
    function emergencyRecovery(address _token, uint256 _amount, address _receiver) external;
}
