// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/ISpotPriceFeed.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../AuthorityUtil.sol";

contract SpotPriceFeed is ISpotPriceFeed, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 100_00;
    uint256 public constant MAX_UPDATE_DURATION = 90 minutes; // 1800 (G: 30 minutes = 1800 seconds)

    string public override description;

    uint256 public lastUpdatedAt;
    uint256 public updateDuration; // 300 = 5 minute (G: 300 = 5 minutes)

    uint256 public maxDeviationBasisPoints; // allowed deviation from primary price

    bool public isMaxDeviationEnabled;
    bool public isFavorFastPriceEnabled;

    mapping (address => uint256) public spotPrices; // token => spot price

    event FeedSpotPrice(address token, uint256 price, address updater);

    function initialize(
        IOptionsAuthority _authority
    ) public initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        description = "SpotPriceFeed";

        updateDuration = 300; // should not be more than MAX_UPDATE_DURATION

        maxDeviationBasisPoints = 250; // (G: 250)
        isFavorFastPriceEnabled = true;
    }

    function setUpdateDuration(uint256 _updateDuration) external override onlyAdmin {
        require(_updateDuration <= MAX_UPDATE_DURATION, "SpotPriceFeed: invalid _updateDuration");
        updateDuration = _updateDuration;
    }

    function setIsMaxDeviationEnabled(bool _isMaxDeviationEnabled) external override onlyAdmin {
        isMaxDeviationEnabled = _isMaxDeviationEnabled;
    }

    function setMaxDeviationBasisPoints(uint256 _maxDeviationBasisPoints) external override onlyAdmin {
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
    }

    function feedSpotPrices(
        address[] memory _tokens,
        uint256[] memory _spotPrices,
        uint256 _deadline
    ) external override onlyKeeper {
        require(_tokens.length == _spotPrices.length, "SpotPriceFeed: invalid tokens and spotPrices length");
        require(block.timestamp <= _deadline, "SpotPriceFeed: DEADLINE_EXPIRED");
        
        lastUpdatedAt = block.timestamp;

        for (uint256 i = 0; i < _tokens.length;) {
            require(_spotPrices[i] > 0, "SpotPriceFeed: INVALID_PRICE");
            spotPrices[_tokens[i]] = _spotPrices[i];
            emit FeedSpotPrice(_tokens[i], _spotPrices[i], msg.sender);
            unchecked { i++; }
        }
    }

    function getSpotPrice(address _token, uint256 _referencePrice, bool _maximise) public override view returns (uint256) {
        require(block.timestamp <= lastUpdatedAt + updateDuration, "SpotPriceFeed: spot prices are not being updated");
        
        uint256 fastPrice = spotPrices[_token];

        // If the _referencePrice is not available, return the fastPrice
        if (_referencePrice == 0) { return fastPrice; }
        
        // If the fastPrice is not available, return the _referencePrice
        if (fastPrice == 0) { return _referencePrice; }
        
        uint256 maxPrice = _referencePrice * (BASIS_POINTS_DIVISOR + maxDeviationBasisPoints) / BASIS_POINTS_DIVISOR;
        uint256 minPrice = _referencePrice * (BASIS_POINTS_DIVISOR - maxDeviationBasisPoints) / BASIS_POINTS_DIVISOR;

        if (favorFastPrice()) {
            if (fastPrice >= minPrice && fastPrice <= maxPrice) {
                return fastPrice;
            }
        }

        if (_maximise) {
            if (_referencePrice > fastPrice) { return _referencePrice; }
            return fastPrice > maxPrice ? maxPrice : fastPrice;
        }

        if (_referencePrice < fastPrice) { return _referencePrice; }
        return fastPrice < minPrice ? minPrice : fastPrice;
    }

    function favorFastPrice() public view returns (bool) {
        if (isMaxDeviationEnabled) {
            return false;
        }

        return isFavorFastPriceEnabled;
    }

    function getLastUpdatedAt() external override view returns (uint256) {
        return lastUpdatedAt;
    }

    function getSpotPriceWithLastUpdatedAt(address _token, uint256 _referencePrice, bool _maximise) external override view returns (uint256, uint256) {
        uint256 spotPrice = getSpotPrice(_token, _referencePrice, _maximise);
        return (spotPrice, lastUpdatedAt);
    }
}
