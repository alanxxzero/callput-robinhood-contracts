// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IFastPriceEvents.sol";
import "../AuthorityUtil.sol";

import "../proxy/OwnableUpgradeable.sol";

contract FastPriceEvents is IFastPriceEvents, OwnableUpgradeable, AuthorityUtil {
    mapping (address => bool) public isPriceFeed;

    event SetIsPriceFeed(address indexed priceFeed, bool isPriceFeed);
    event MarkPriceUpdate(uint256 indexed _optionTokenId, uint256 price, address indexed priceFeed);
    event RiskPremiumUpdate(uint256 indexed _optionTokenId, uint256 riskPremium, uint256 requestIndex, address indexed priceFeed);

    function initialize(IOptionsAuthority _authority) public initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);
    }

    function setIsPriceFeed(address _priceFeed, bool _isPriceFeed) external onlyAdmin {
      isPriceFeed[_priceFeed] = _isPriceFeed;
      emit SetIsPriceFeed(_priceFeed, _isPriceFeed);
    }

    function emitMarkPriceEvent(uint256 _optionTokenId, uint256 _price) external override {
      require(isPriceFeed[msg.sender], "FastPriceEvents: invalid sender");
      emit MarkPriceUpdate(_optionTokenId, _price, msg.sender);
    }

    function emitRiskPremiumEvent(uint256 _optionTokenId, uint256 _riskPremium, uint256 _requestIndex) external override {
      require(isPriceFeed[msg.sender], "FastPriceEvents: invalid sender");
      emit RiskPremiumUpdate(_optionTokenId, _riskPremium, _requestIndex, msg.sender);
    }
}
