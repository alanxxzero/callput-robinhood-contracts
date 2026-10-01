// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IPrimaryOracle {
    function getPrice(address token, bool maximise) external view returns (uint256);
}