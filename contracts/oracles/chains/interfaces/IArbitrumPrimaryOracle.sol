// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IArbitrumPrimaryOracle {
    function setPriceSampleSpace(uint256 _priceSampleSpace) external;
    function setTokenConfig(address _token, address _priceFeed, uint256 _priceDecimals) external;
}
