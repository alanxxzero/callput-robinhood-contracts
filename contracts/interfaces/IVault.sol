// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IVaultUtils.sol";
import "../Utils.sol";

interface IVault {
    function isPositionEnabled() external view returns (bool);
    function isBuySellSwapEnabled() external view returns (bool);

    function vaultUtils() external view returns (IVaultUtils);

    function optionsMarket() external view returns (address);
    function settleManager() external view returns (address);
    function controller() external view returns (address);
    function vaultPriceFeed() external view returns (address);
    function usdg() external view returns (address);

    function thresholdDays() external view returns (uint40);

    function whitelistedTokenCount() external view returns (uint256);
    function totalTokenWeights() external view returns (uint256);
    function whitelistedTokens(uint256) external view returns (address);

    function isManager(address _manager) external view returns (bool);

    function isWhitelistedToken(address _token) external view returns (bool);
    function isUnderlyingAssetToken(address _token) external view returns (bool);
    function isStableToken(address _token) external view returns (bool);
    function tokenDecimals(address _token) external view returns (uint256);
    function tokenBalances(address _token) external view returns (uint256);
    function tokenWeights(address _token) external view returns (uint256);

    function usdgAmounts(address _token) external view returns (uint256);
    function maxUsdgAmounts(address _token) external view returns (uint256);

    function poolAmounts(address _token) external view returns (uint256);
    function reservedAmounts(address _token) external view returns (uint256);
    function utilizedAmounts(address _token) external view returns (uint256);
    function pendingMpAmounts(address _token) external view returns (uint256);
    function pendingRpAmounts(address _token) external view returns (uint256);

    function bufferAmounts(address _token) external view returns (uint256);
    function feeReserves(address _token) external view returns (uint256);
    function decreaseToleranceAmount(address _token) external view returns (uint256);

    function setManager(address _manager, bool _isManager) external;

    //////////////////////////////////////////////
    //  Setters                                 //
    //////////////////////////////////////////////

    function setIsPositionEnabled(bool _isPositionEnabled) external;
    function setIsBuySellSwapEnabled(bool _isBuySellSwapEnabled) external;
    function setThresholdDays(uint40 _thresholdDays) external;
    function setBufferAmount(address _token, uint256 _amount) external;
    function setUsdgAmount(address _token, uint256 _amount) external;
    function setContracts(
        IVaultUtils _vaultUtils,
        address _optionsMarket,
        address _settleManager,
        address _controller,
        address _vaultPriceFeed,
        address _usdg
    ) external;
    function setTokenConfig(
        address _token,
        uint256 _tokenDecimals,
        uint256 _redemptionBps,
        uint256 _maxUsdgAmount,
        bool _isUnderlyingAssetToken,
        bool _isStableToken,
        uint256 _bufferAmount
    ) external;
    function directPoolDeposit(address _token) external;
    function withdrawFees(address _token, address _receiver) external returns (uint256);
    function updatePendingAmount(address _token) external;


    //////////////////////////////////////////////
    //               Get Functions              //
    //////////////////////////////////////////////

    function whitelistedTokensLength() external view returns (uint256);
    function getSpotPrice(address _token, bool _maximise) external view returns (uint256);
    function getSettlePrice(address _tokenAddress, uint256 _expiry) external view returns (uint256);
    function getTargetUsdgAmount(address _token) external view returns (uint256);
    function getRedemptionAmount(address _token, uint256 _usdgAmount) external view returns (uint256);
    function getMainStableAsset() external view returns (address);
    function getUnderlyingAssetByIndex(uint16 _underlyingAssetIndex) external view returns (address);


    //////////////////////////////////////////////
    //            OlpManager Related            //
    //////////////////////////////////////////////

    function buyUSDG(address _token, address _receiver) external returns (uint256);
    function sellUSDG(address _token, address _receiver) external returns (uint256);
    function swap(address _tokenIn, address _tokenOut, address _receiver) external returns (uint256);


    //////////////////////////////////////////////
    //              Option Related              //
    //////////////////////////////////////////////

    function openPosition(
        address _account,
        uint256 _requestIndex,
        uint256 _optionTokenId,
        uint16 _underlyingAssetIndex,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        address _quoteToken,
        address _receiver
    ) external returns (
        uint256 sizeOut,
        uint256 executionPrice,
        address utilizedToken,
        uint256 utilizedAmount,
        address tokenOut,
        uint256 amountOut,
        uint256 afterFeePaidAmount
    );
    function closePosition(
        address _account,
        uint256 _requestIndex,
        uint256 _optionTokenId,
        uint256 _size,
        uint16 _underlyingAssetIndex,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        address _quoteToken,
        address _receiver
    ) external returns (
        uint256 executionPrice,
        uint256 amountOut,
        uint256 totalExecutionPriceAmount,
        uint256 collateralAmount
    );
    function settlePosition(
        address _account,
        uint256 _size,
        uint16 _underlyingAssetIndex,
        uint40 _expiry,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        bool _isAccountSourceVault,
        address _quoteToken,
        address _receiver
    ) external returns (
        uint256 settlePrice,
        uint256 amountOut,
        uint256 totalIntrinsicAmount
    );
    function clearPosition(
        uint256 _size,
        uint16 _underlyingAssetIndex,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices
    ) external;
    function settleVaultPosition(
        address[] memory _path,
        uint16 _underlyingAssetIndex,
        uint256 _optionTokenId
    ) external returns (uint256);


    //////////////////////////////////////////////
    //             Utility Functions            //
    //////////////////////////////////////////////

    function tokenToUsdMin(address _token, uint256 _tokenAmount) external view returns (uint256);
    function usdToToken(address _token, uint256 _usdAmount, bool _maximise) external view returns (uint256);
    function isEnabledToken(address _token) external view returns (bool);
}
