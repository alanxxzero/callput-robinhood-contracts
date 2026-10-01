// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IRewardDistributor {
    function tokensPerInterval() external view returns (uint256);
}