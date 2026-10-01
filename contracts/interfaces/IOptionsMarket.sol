// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IOptionsMarket {
    struct Option {
        uint16 underlyingAssetIndex;
        address underlyingAsset;
        uint40 expiry;
        uint48 strikePrice;
        bool isActive;
    }
    
    struct TradingHours {
        bool is24HourTrading;           
        uint8 startHour;                // UTC based start hour (0-23)
        uint8 endHour;                  // UTC based end hour (0-23)
        bool enforceOnClose;            
        uint8 excludedDaysOfWeekMask;   // bitmask of excluded days of week (0=Sunday, 1=Monday, ..., 6=Saturday)
        uint256[] excludedDates;        // excluded dates (timestamp / 86400, UTC based)
    }
    
    function mainStableAsset() external view returns (address);

    function indexToUnderlyingAsset(uint16) external view returns (address);
    function underlyingAssetToIndex(address) external view returns (uint16);
    function underlyingAssetToOptionsToken(address) external view returns (address);
    function optionsTokenToUnderlyingAsset(address) external view returns (address);
    function isUnderlyingAssetActive(address) external view returns (bool);

    function setMainStableAsset(address _mainStableAsset) external;
    function addUnderlyingAsset(address _underlyingAsset, address _optionsToken) external;
    function setIsUnderlyingAsset(uint16 _underlyingAssetIndex, bool _isUnderlyingAssetActive) external;

    function getOptionId(
        uint16 _underlyingAssetIndex,
        uint40 _expiry,
        uint48 _strikePrice
    ) external pure returns (bytes32);
    function getOptionTokenId (
        uint16 _underlyingAssetIndex,
        uint40 _expiry,
        uint8 _length,
        bool[4] memory _isBuys,
        bytes32[4] memory _optionIds,
        bool[4] memory _isCall,
        uint8 _vaultIndex
    ) external view returns (uint256, bytes32[4] memory);
    function getMainStableAsset() external view returns (address, uint8);
    function getUnderlyingAssetByIndex(uint16 _underlyingAssetIndex) external view returns (address, uint8);
    function getOptionsTokenByIndex (uint16 _underlyingAssetIndex) external view returns (address);
    function getOptionDetail(bytes32 _key) external view returns (uint16, address, uint40, uint48);
    function getOptionsBatch(bytes32[] memory _keys) external view returns (Option[] memory);

    function isOptionAvailable(bytes32 _key) external view returns (bool);
    function validateOptionIds(uint16 _underlyingAssetIndex, uint8 _length, bytes32[4] memory _optionIds) external view returns (uint40);

    function addOptions(address _underlyingAsset, uint40 _expiry, uint48[] memory _strikePrices) external;
    function removeOptions(bytes32[] memory _keys) external;

    function tradingHours(uint16) external view returns (TradingHours memory);
    function isTradingAllowed(uint16 _underlyingAssetIndex, uint256 _timestamp, bool _isOpen) external view returns (bool);
    function isTradingAllowedNow(uint16 _underlyingAssetIndex, bool _isOpen) external view returns (bool);
    function setTradingHours(
        uint16 _underlyingAssetIndex,
        bool _is24HourTrading,
        uint8 _startHour,
        uint8 _endHour,
        bool _enforceOnClose,
        uint8[] memory _excludedDaysOfWeek,
        uint256[] memory _excludedDates
    ) external;
}
