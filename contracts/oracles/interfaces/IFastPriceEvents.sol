// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IFastPriceEvents {
    function emitMarkPriceEvent(uint256 _optionTokenId, uint256 _price) external;
    function emitRiskPremiumEvent(uint256 _optionTokenId, uint256 _riskPremium, uint256 _requestIndex) external;
}
