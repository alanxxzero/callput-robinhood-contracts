// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../Utils.sol";

interface IVaultUtils {    
    enum FeeType {
        OpenPositionFee, // Fee incurred during Open
        OpenComboPositionFee,
        ClosePositionFee, // Fee incurred during Close
        CloseComboPositionFee,
        SettlePositionFee, // Fee incurred during Settle
        TaxFee, // Fee incurred based on the difference in TargetAmount
        StableTaxFee, // Fee incurred based on the difference in TargetAmount for Stable 
        MintBurnFee, // Fee incurred during BuyUSDG, SellUSDG
        SwapFee, // Fee incurred during Swap
        StableSwapFee // Fee incurred during Swap for Stable
    }

    enum PriceType {
        MP,
        RP
    }

    struct OptionToken {
        uint256 optionTokenId;
        uint256 size;
    }

    function hasDynamicFees() external view returns (bool);

    function isSelfExpiryAdded(uint256) external view returns (bool);
    function isPositionAtSelfExpirySettled(uint256) external view returns (bool);
    function optionTokensAtSelfExpiryStart(uint256) external view returns (uint256);


    //////////////////////////////////////////////
    //  General Util Functions                  //
    //////////////////////////////////////////////

    function getWhitelistedTokens() external view returns (address[] memory);
    function getEnabledTokens() external view returns (address[] memory);
    function calculateItmStatusAndIntrinsicUsd(
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        uint256 _settlePrice
    ) external pure returns (bool isItm, uint256 intrinsicUsd);


    //////////////////////////////////////////////
    //  Fee Management                          //
    //////////////////////////////////////////////
    
    function getPositionFeeInfo(
        address _account,
        Utils.Strategy _strategy,
        address _token,
        uint256 _amount,
        address _underlyingAsset,
        uint256 _size,
        uint256 _price,
        bool _isOpen,
        bool _isSettle,
        uint openRequestIndex
    ) external view returns (uint256, uint256, uint256, uint256, address, uint256, bool);
    function getPositionFeeBasisPoints(
        address _account,
        Utils.Strategy _strategy,
        bool _isOpen,
        bool _isSettle
    ) external view returns (uint256, uint256, address, uint256);
    function getBuyUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) external view returns (uint256);
    function getSellUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) external view returns (uint256);
    function getSwapFeeBasisPoints(address _tokenIn, address _tokenOut, uint256 _usdgAmount) external view returns (uint256);
    function getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) external view returns (uint256);


    //////////////////////////////////////////////
    //  MP and RP Management                    //
    //////////////////////////////////////////////

    function releaseRate(PriceType _priceType, address _token) external view returns (uint256);
    function periodFinish(PriceType _priceType, address _token) external view returns (uint256);
    function setReleaseDuration(address _token, uint256 _duration, PriceType _priceType) external;
    function notifyPendingAmount(
        PriceType _priceType,
        address _token,
        uint256 _pendingUsd,
        uint256 _pendingAmount
    ) external;
    function getReleaseAmountAll(address _token) external returns (uint256, uint256);


    //////////////////////////////////////////////
    //  Management of Vault's Positions         //
    //////////////////////////////////////////////

    function getSelfOriginExpiries() external view returns (uint256[] memory);
    function getSelfOriginExpiriesLength() external view returns (uint256);
    function getOptionTokensAtSelfOriginExpiry(uint256 _expiry) external view returns (OptionToken[] memory);
    function getOptionTokensLengthAtSelfExpiry(uint256 _expiry) external view returns (uint256);
    function getSelfOriginExpiriesToSettle() external view returns (uint256[] memory);
    function isInSettlementProgress() external view returns (bool);
    function updateVaultPositionAfterTrade(
        uint256 _expiry,
        uint256 _optionTokenId,
        uint256 _size,
        bool _isAdd
    ) external;

    // utils for manual settlement
    function addExpiryToArray(uint256 _expiry, bool _isSettle) external;
    function removeExpiryFromArray(uint256 _expiry, bool _isSettle) external;
    function setIsPositionSettled (uint256 _expiry, bool _isPositionSettled) external;
    function setOptionTokensStart(uint256 _expiry, uint256 _optionTokensStart) external;

    // utils for auto settlement
    function prepareExpiriesToSettle() external;
    function settleSelfOriginPositions(uint256 _expiry, uint256 _endIndex) external returns (bool);
}