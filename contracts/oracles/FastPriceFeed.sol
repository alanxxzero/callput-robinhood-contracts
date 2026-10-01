// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IFastPriceFeed.sol";
import "./interfaces/IFastPriceEvents.sol";
import "../interfaces/IPositionManager.sol";

import "../AuthorityUtil.sol";
import "../proxy/OwnableUpgradeable.sol";

contract FastPriceFeed is IFastPriceFeed, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant SERVER_PRICE_PRECISION = 10 ** 3;

    // uint256(~0) is 256 bits of 1s
    // shift the 1s by (256 - 32) to get (256 - 32) 0s followed by 32 1s
    // uint256 constant public BITMASK_32 = uint256(~0) >> (256 - 32);
    uint256 constant public BITMASK_32 = type(uint256).max >> (256 - 32);
    uint256 public constant MAX_UPDATE_DURATION = 30 minutes;

    address public fastPriceEvents;

    uint256 public updateDuration; // 60 = 1 minute // when using prices, the last updated timestamp should not be more than updateDuration
    uint256 public maxTimeDeviation; // 60 = 1 minute // when updating prices, the timestamp from the server should not be more than this value away from the current block.timestamp

    mapping (uint256 => uint256) public markPrice; // optionTokenId => option price
    mapping (uint256 => mapping(uint256 => uint256)) public riskPremium; // optionTokenId => request index => option price

    mapping (uint256 => uint256) public lastUpdatedAt; // optionTokenId => last updated timestamp

    event SetFastPriceEvents(address indexed fastPriceEvents);
    event SetMaxTimeDeviation(uint256 indexed maxTimeDeviation);
    event SetUpdateDuration(uint256 indexed updateDuration);
    event SetLastUpdatedAt(uint256 indexed optionTokenId, uint256 lastUpdatedAt);

    function initialize(
        address _fastPriceEvents,
        IOptionsAuthority _authority
    ) public initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        updateDuration = 60; // should not be more than MAX_UPDATE_DURATION
        maxTimeDeviation = 60;

        fastPriceEvents = _fastPriceEvents;
    }

    function setFastPriceEvents(address _fastPriceEvents) external onlyAdmin {
        fastPriceEvents = _fastPriceEvents;
        emit SetFastPriceEvents(_fastPriceEvents);
    }

    function setMaxTimeDeviation(uint256 _maxTimeDeviation) external onlyAdmin {
        maxTimeDeviation = _maxTimeDeviation;
        emit SetMaxTimeDeviation(_maxTimeDeviation);
    }

    function setUpdateDuration(uint256 _updateDuration) external override onlyAdmin {
        require(_updateDuration <= MAX_UPDATE_DURATION, "FastPriceFeed: invalid _updateDuration");
        updateDuration = _updateDuration;
        emit SetUpdateDuration(_updateDuration);
    }

    // emergency
    function setLastUpdatedAt(uint256 _optionTokenId, uint256 _lastUpdatedAt) external onlyAdmin {
        lastUpdatedAt[_optionTokenId] = _lastUpdatedAt;
        emit SetLastUpdatedAt(_optionTokenId, _lastUpdatedAt);
    }

    function setPricesAndRiskPremiums(uint256[] memory _markPriceArray, uint256[] memory _riskPremiumArray, uint256[] memory _optionTokenIds, uint256[] memory _requestIndexes, uint256 _timestamp) external onlyPositionKeeper {
        require (_markPriceArray.length == _riskPremiumArray.length && _markPriceArray.length == _optionTokenIds.length && _markPriceArray.length == _requestIndexes.length, "FastPriceFeed: invalid lengths");

        for (uint256 i = 0; i < _optionTokenIds.length;) {
            bool shouldUpdate = _setLastUpdatedValues(_optionTokenIds[i], _timestamp);

            if (shouldUpdate) {
                _setMarkPrice(_optionTokenIds[i], _markPriceArray[i], fastPriceEvents);
                _setRiskPremium(_optionTokenIds[i], _riskPremiumArray[i], _requestIndexes[i], fastPriceEvents);
            }

            unchecked { i++; }
        }
    }

    function setPricesAndRiskPremiumsWithBits(uint256[] memory _markPriceBitArray, uint256[] memory _riskPremiumBitArray, uint256[] memory _optionTokenIds, uint256[] memory _requestIndexes, uint256 _timestamp) external onlyPositionKeeper {
        _setPricesAndRiskPremiumsWithBits(_markPriceBitArray, _riskPremiumBitArray, _optionTokenIds, _requestIndexes, _timestamp);
    }

    function setPricesAndRiskPremiumsWithBitsAndExecute(
        address _positionManager,
        uint256[] memory _markPriceBitArray,
        uint256[] memory _riskPremiumBitArray,
        uint256[] memory _optionTokenIds,
        uint256[] memory _requestIndexes,
        uint256 _timestamp,
        uint256 _endIndexForPositions,
        uint256 _maxPositions
    ) external onlyPositionKeeper {
        _setPricesAndRiskPremiumsWithBits(_markPriceBitArray, _riskPremiumBitArray, _optionTokenIds, _requestIndexes, _timestamp);

        IPositionManager positionManager = IPositionManager(_positionManager);

        uint256 maxEndIndex = positionManager.positionRequestKeysStart() + _maxPositions;

        if (_endIndexForPositions > maxEndIndex) {
            _endIndexForPositions = maxEndIndex;
        }

        positionManager.executePositions(_endIndexForPositions, payable(msg.sender));
    }
    
    function getMarkPrice(uint256 _optionTokenId) external override view returns (uint256) {
        uint256 lastUpdatedAt_ = lastUpdatedAt[_optionTokenId];
        // If the last update time is more than the update duration, then the price is stale
        require(block.timestamp <= lastUpdatedAt_ + updateDuration, "FastPriceFeed: mark price not stale");

        uint256 fastMarkPrice = markPrice[_optionTokenId];
        require(fastMarkPrice > 0, "FastPriceFeed: invalid fastMarkPrice");

        return fastMarkPrice;
    }

    function getRiskPremium(uint256 _optionTokenId, uint256 _requestIndex) external override view returns (uint256) {
        uint256 lastUpdatedAt_ = lastUpdatedAt[_optionTokenId];
        // If the last update time is more than the update duration, then the price is stale
        require(block.timestamp <= lastUpdatedAt_ + updateDuration, "FastPriceFeed: mark price not stale");

        uint256 fastRiskPremium = riskPremium[_optionTokenId][_requestIndex];

        return fastRiskPremium;
    }

    // one bit contains prices of up to 8 option tokens 
    // so, 2 length of markPriceBitArray can contain prices of up to 16 option tokens
    function _setPricesAndRiskPremiumsWithBits(uint256[] memory _markPriceBitArray, uint256[] memory _riskPremiumBitArray, uint256[] memory _optionTokenIds, uint256[] memory _requestIndexes, uint256 _timestamp) private { 
        require(_markPriceBitArray.length == _riskPremiumBitArray.length, "FastPriceFeed: mismatched bit array lengths");

        uint256 expectedMaxOptionCount = _markPriceBitArray.length * 8;
        require(
            _optionTokenIds.length <= expectedMaxOptionCount && 
            _optionTokenIds.length > expectedMaxOptionCount - 8 &&
            _requestIndexes.length <= expectedMaxOptionCount && 
            _requestIndexes.length > expectedMaxOptionCount - 8,
            "FastPriceFeed: OptionTokenIds or RequestIndexes length out of expected range"
        );

        for (uint256 i = 0; i < _markPriceBitArray.length;) {
            uint256 markPriceBits = _markPriceBitArray[i];
            uint256 riskPremiumBits = _riskPremiumBitArray[i];

            // 8 slots of 32 bits each
            for (uint256 j = 0; j < 8;) {
                uint256 index = i * 8 + j;

                if (index >= _optionTokenIds.length) { return; }

                uint256 optionTokenId = _optionTokenIds[index];
                uint256 requestIndex = _requestIndexes[index];
                bool shouldUpdate = _setLastUpdatedValues(optionTokenId, _timestamp);

                if (shouldUpdate) {
                    uint256 startBit = 32 * j;

                    uint256 _markPrice = (markPriceBits >> startBit) & BITMASK_32;
                    uint256 adjustedMarkPrice = (_markPrice * PRICE_PRECISION) / SERVER_PRICE_PRECISION;

                    uint256 _riskPremium = (riskPremiumBits >> startBit) & BITMASK_32;
                    uint256 adjustedRiskPremium = (_riskPremium * PRICE_PRECISION) / SERVER_PRICE_PRECISION;

                    _setMarkPrice(optionTokenId, adjustedMarkPrice, fastPriceEvents);
                    _setRiskPremium(optionTokenId, adjustedRiskPremium, requestIndex, fastPriceEvents);
                }

                unchecked { j++; }
            }

            unchecked { i++; }
        }
    }

    function _setMarkPrice(uint256 _optionTokenId, uint256 _markPrice, address _fastPriceEvents) private {
        markPrice[_optionTokenId] = _markPrice;
        _emitMarkPriceEvent(_fastPriceEvents, _optionTokenId, _markPrice);
    }

    function _setRiskPremium(uint256 _optionTokenId, uint256 _riskPremium, uint256 _requestIndex, address _fastPriceEvents) private {
        riskPremium[_optionTokenId][_requestIndex] = _riskPremium;
        _emitRiskPremiumEvent(_fastPriceEvents, _optionTokenId, _requestIndex, _riskPremium);
    }

    function _emitMarkPriceEvent(address _fastPriceEvents, uint256 _optionTokenId, uint256 _markPrice) private {
        if (_fastPriceEvents == address(0)) {
            return;
        }
        IFastPriceEvents(_fastPriceEvents).emitMarkPriceEvent(_optionTokenId, _markPrice);
    }
    
    function _emitRiskPremiumEvent(address _fastPriceEvents, uint256 _optionTokenId, uint256 _riskPremium, uint256 _requestIndex) private {
        if (_fastPriceEvents == address(0)) {
            return;
        }
        IFastPriceEvents(_fastPriceEvents).emitRiskPremiumEvent(_optionTokenId, _riskPremium, _requestIndex);
    }

    function _setLastUpdatedValues(uint256 _optionTokenId, uint256 _timestamp) private returns (bool) {
        // _timestamp: from server
        // block.timestamp: from onchain
        // (allowed) maxTimeDeviation: max allowed deviation between server and onchain
        uint256 _maxTimeDeviation = maxTimeDeviation;
        require(_timestamp > (block.timestamp - _maxTimeDeviation), "FastPriceFeed: _timestamp below allowed range");
        require(_timestamp < (block.timestamp + _maxTimeDeviation), "FastPriceFeed: _timestamp exceeds allowed range");

        // do not update prices if _timestamp is before the current lastUpdatedAt value
        if (_timestamp < lastUpdatedAt[_optionTokenId]) {
            return false;
        }

        lastUpdatedAt[_optionTokenId] = _timestamp;

        return true;
    }
}
