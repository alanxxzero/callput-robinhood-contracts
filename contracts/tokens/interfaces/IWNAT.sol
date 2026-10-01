// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IWNAT {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
