// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/ISettlePriceFeed.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../AuthorityUtil.sol";

contract SettlePriceFeed is ISettlePriceFeed, OwnableUpgradeable, AuthorityUtil {
    string public override description;

    mapping (address => mapping (uint256 => uint256)) public settlePrices; // token => timestamp => settle price

    event FeedSettlePrice(address indexed underlyingAsset, uint256 indexed expiry, uint256 settlePrice, address updater);

    function initialize(
        IOptionsAuthority _authority
    ) public initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        description = "SettlePriceFeed";
    }

    function feedSettlePrices(address[] memory _tokens, uint256[] memory _settlePrices, uint256 _expiry) external override onlyKeeper {
        require(_tokens.length == _settlePrices.length, "SettlePriceFeed: invalid tokens and settlePrices length");
        require(_expiry <= block.timestamp, "SettlePriceFeed: EXPIRY_NOT_PASSED");

        for (uint256 i = 0; i < _tokens.length;) {
            require(_settlePrices[i] > 0, "SettlePriceFeed: INVALID_PRICE");
            settlePrices[_tokens[i]][_expiry] = _settlePrices[i];

            emit FeedSettlePrice(_tokens[i], _expiry, _settlePrices[i], msg.sender);

            unchecked { i++; }
        }
    }

    function getSettlePrice(address _token, uint256 _expiry) external override view returns (uint256) {
        return settlePrices[_token][_expiry];
    }
}
