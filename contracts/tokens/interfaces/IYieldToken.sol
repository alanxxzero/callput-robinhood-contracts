// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IYieldToken {
    function totalStaked() external view returns (uint256);
    function stakedBalance(address _account) external view returns (uint256);
}
