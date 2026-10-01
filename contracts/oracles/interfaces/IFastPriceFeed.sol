// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFastPriceFeed {
    function lastUpdatedAt(uint256 _tokenId) external view returns (uint256);
    function setUpdateDuration(uint256 _priceDuration) external;

    function getMarkPrice(uint256 _optionTokenId) external view returns (uint256);
    function getRiskPremium(uint256 _optionTokenId, uint256 _requestIndex) external view returns (uint256);
}
