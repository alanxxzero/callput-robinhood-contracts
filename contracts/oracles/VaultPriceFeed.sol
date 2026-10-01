// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IVaultPriceFeed.sol";
import "./interfaces/IFastPriceFeed.sol";
import "./interfaces/ISettlePriceFeed.sol";
import "./interfaces/IPositionValueFeed.sol";
import "./interfaces/ISpotPriceFeed.sol";
import "./chains/interfaces/IPrimaryOracle.sol";

import "../interfaces/IPositionManager.sol";
import "../AuthorityUtil.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../Utils.sol";

contract VaultPriceFeed is IVaultPriceFeed, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 100_00;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;

    // @desc The address of the primary oracle
    // @info
    // - For Arbitrum, the primary oracle is the Chainlink oracle
    // - For Berachain, there is no primary oracle
    address public primaryOracle;
    // @desc The address of the secondary spot price feed
    // @info
    // - For Arbitrum, should be enabled
    // - For Berachain, should be enabled
    address public secondarySpotPriceFeed;

    bool public isPrimaryOracleEnabled;
    bool public isSecondarySpotEnabled;

    address public fastPriceFeed;
    address public settlePriceFeed;
    address public positionValueFeed;

    uint256 public maxStrictPriceDeviation;

    mapping (address => uint256) public spreadBasisPoints;
    mapping (address => bool) public supportedTokens;
    // Oracle can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping (address => bool) public strictStableTokens;

    address public positionManager;

    // @desc Minimum mark price for each underlying asset, denominated in PRICE_PRECISION
    // @info
    // - BTC: 60 * PRICE_PRECISION ($60)
    // - ETH: 3 * PRICE_PRECISION ($3)
    // - INDEX [1, 2] for ARB [BTC, ETH], INDEX [3, 4] for BERA BARTIO
    mapping (uint16 => uint256) public minMarkPrices; // underlying asset index -> mark price

    event SetPrimaryOracle(address indexed primaryOracle, bool indexed isPrimaryOracleEnabled);
    event SetSecondarySpotPriceFeed(address indexed secondarySpotPriceFeed, bool indexed isSecondarySpotEnabled);
    event SetFastPriceFeed(address indexed fastPriceFeed);
    event SetSettlePriceFeed(address indexed settlePriceFeed);
    event SetPositionValueFeed(address indexed positionValueFeed);
    event SetPositionManager(address indexed positionManager);
    event SetMaxStrictPriceDeviation(uint256 indexed maxStrictPriceDeviation);
    event SetSpreadBasisPoints(address indexed token, uint256 spreadBasisPoints);
    event SetTokenConfig(address indexed token, bool isRegistered, bool isStrictStable);
    event SetMinMarkPrice(uint16 indexed underlyingAssetIndex, uint256 minMarkPrice);

    function initialize(IOptionsAuthority _authority) external initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        maxStrictPriceDeviation = 0.05 * 10 ** 30; // 50000000000000000000000000000
    }

    function setPrimaryOracle(address _primaryOracle, bool _isPrimaryOracleEnabled) external onlyAdmin {
        if (_isPrimaryOracleEnabled) {
            require(_primaryOracle != address(0), "VaultPriceFeed: invalid primaryOracle");
        }

        primaryOracle = _primaryOracle;
        isPrimaryOracleEnabled = _isPrimaryOracleEnabled;

        emit SetPrimaryOracle(_primaryOracle, _isPrimaryOracleEnabled);
    }

    function setSecondarySpotPriceFeed(address _secondarySpotPriceFeed, bool _isSecondarySpotEnabled) external onlyAdmin {
        if (_isSecondarySpotEnabled) {
            require(_secondarySpotPriceFeed != address(0), "VaultPriceFeed: invalid secondarySpotPriceFeed");
        }
        
        secondarySpotPriceFeed = _secondarySpotPriceFeed;
        isSecondarySpotEnabled = _isSecondarySpotEnabled;

        emit SetSecondarySpotPriceFeed(_secondarySpotPriceFeed, _isSecondarySpotEnabled);
    }

    function setPriceFeeds(
        address _fastPriceFeed,
        address _settlePriceFeed,
        address _positionValueFeed
    ) external onlyAdmin {
        require(
            _fastPriceFeed != address(0) &&
            _settlePriceFeed != address(0) &&
            _positionValueFeed != address(0),
            "VaultPriceFeed: invalid addresses"
        );

        fastPriceFeed = _fastPriceFeed;
        settlePriceFeed = _settlePriceFeed;
        positionValueFeed = _positionValueFeed;
    }
    
    function setFastPriceFeed(address _fastPriceFeed) external onlyAdmin {
        require(_fastPriceFeed != address(0), "VaultPriceFeed: invalid fastPriceFeed");
        fastPriceFeed = _fastPriceFeed;
        emit SetFastPriceFeed(_fastPriceFeed);
    }

    function setSettlePriceFeed(address _settlePriceFeed) external onlyAdmin {
        require(_settlePriceFeed != address(0), "VaultPriceFeed: invalid settlePriceFeed");
        settlePriceFeed = _settlePriceFeed;
        emit SetSettlePriceFeed(_settlePriceFeed);
    }

    function setPositionValueFeed(address _positionValueFeed) external onlyAdmin {
        require(_positionValueFeed != address(0), "VaultPriceFeed: invalid positionValueFeed");
        positionValueFeed = _positionValueFeed;
        emit SetPositionValueFeed(_positionValueFeed);
    }

    function setPositionManager(address _positionManager) external onlyAdmin {
        require(_positionManager != address(0), "VaultPriceFeed: invalid positionManager");
        positionManager = _positionManager;
        emit SetPositionManager(_positionManager);
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external override onlyAdmin {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
        emit SetMaxStrictPriceDeviation(_maxStrictPriceDeviation);
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external override onlyAdmin {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
        emit SetSpreadBasisPoints(_token, _spreadBasisPoints);
    }

    function setTokenConfig(address _token, bool _isSupported, bool _isStrictStable) external override onlyAdmin {
        require(_token != address(0), "VaultPriceFeed: invalid addresses when setting token config"); 
        supportedTokens[_token] = _isSupported;
        strictStableTokens[_token] = _isStrictStable;
        emit SetTokenConfig(_token, _isSupported, _isStrictStable);
    }

    function setMinMarkPrice(uint16 _underlyingAssetIndex, uint256 _minComboMarkPrice) external override onlyAdmin {
        minMarkPrices[_underlyingAssetIndex] = _minComboMarkPrice;
        emit SetMinMarkPrice(_underlyingAssetIndex, _minComboMarkPrice);
    }

    function getSettlePrice(address _token, uint256 _expiry) external view override returns (uint256) {    
        require(settlePriceFeed != address(0), "VaultPriceFeed: settle price feed not set");
        uint256 settlePrice = ISettlePriceFeed(settlePriceFeed).getSettlePrice(_token, _expiry);
        require(settlePrice > 0, "VaultPriceFeed: invalid settle price");
        return settlePrice;
    }

    function getAPV(address _vault) external view override returns (uint256) {
        require(positionValueFeed != address(0), "VaultPriceFeed: absolute position value feed not set");
        uint256 value = IPositionValueFeed(positionValueFeed).getAPV(_vault);
        return value;
    }

    function getPVAndSign(address _vault) external view override returns (uint256, bool) {
        require(positionValueFeed != address(0), "VaultPriceFeed: position value feed not set");
        (uint256 value, bool isNegative) = IPositionValueFeed(positionValueFeed).getPVAndSign(_vault);
        return (value, isNegative);
    }

    function getMarkPrice(uint256 _optionTokenId, uint256 _requestIndex) public override view returns (uint256) {
        require(fastPriceFeed != address(0), "VaultPriceFeed: secondary price feed not set");
        uint256 markPrice = IFastPriceFeed(fastPriceFeed).getMarkPrice(_optionTokenId);
        validateLeverageLimit(_optionTokenId, _requestIndex, markPrice);
        return markPrice;
    }

    function getRiskPremium(uint256 _optionTokenId, uint256 _requestIndex) public override view returns (uint256) {
        require(fastPriceFeed != address(0), "VaultPriceFeed: secondary price feed not set");
        return IFastPriceFeed(fastPriceFeed).getRiskPremium(_optionTokenId, _requestIndex);
    }

    function getMarkPriceAndRiskPremium(uint256 _optionTokenId, uint256 _requestIndex) public override view returns (uint256, uint256) {
        uint256 markPrice = getMarkPrice(_optionTokenId, _requestIndex);
        uint256 riskPremium = getRiskPremium(_optionTokenId, _requestIndex);
        return (markPrice, riskPremium);
    }
    
    function getExecutionPrice(uint256 _optionTokenId, uint256 _requestIndex, bool _addRiskPremium) public override view returns (uint256) {
        uint256 markPrice = getMarkPrice(_optionTokenId, _requestIndex);
        uint256 riskPremium = getRiskPremium(_optionTokenId, _requestIndex);

        if (!_addRiskPremium && riskPremium > markPrice) {
            return 0;
        }

        uint256 executionPrice = _addRiskPremium ? markPrice + riskPremium : markPrice - riskPremium;
        return executionPrice;
    }
    
    function getSpotPrice(address _token, bool _maximise) public override view returns (uint256) {
        require(supportedTokens[_token], "VaultPriceFeed: token not supported");
        require(isPrimaryOracleEnabled || isSecondarySpotEnabled, "VaultPriceFeed: no price feed enabled");

        uint256 price = 0;

        if (isPrimaryOracleEnabled) {
            price = getOraclePrice(_token, _maximise);
        }

        if (isSecondarySpotEnabled) {
            price = getSecondarySpotPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta;

            if (price > ONE_USD) {
                unchecked { delta = price - ONE_USD; }
            } else {
                unchecked { delta = ONE_USD - price; }
            }

            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price * (BASIS_POINTS_DIVISOR + _spreadBasisPoints) / BASIS_POINTS_DIVISOR;
        }

        return price * (BASIS_POINTS_DIVISOR - _spreadBasisPoints) / BASIS_POINTS_DIVISOR;
    }

    function getSecondarySpotPrice(address _token, uint256 _referencePrice, bool _maximise) public view returns (uint256) {
        require(secondarySpotPriceFeed != address(0), "VaultPriceFeed: secondary spot price feed not set");
        uint256 spotPrice = ISpotPriceFeed(secondarySpotPriceFeed).getSpotPrice(_token, _referencePrice, _maximise);
        require(spotPrice > 0, "VaultPriceFeed: invalid spot price");
        return spotPrice;
    }

    function getOraclePrice(address _token, bool _maximise) public override view returns (uint256) {
        require(primaryOracle != address(0), "VaultPriceFeed: primary oracle not set");
        uint256 price = IPrimaryOracle(primaryOracle).getPrice(_token, _maximise);
        require(price > 0, "VaultPriceFeed: invalid oracle price");
        return price;
    }

    function validateLeverageLimit(
        uint256 _optionTokenId,
        uint256 _requestIndex,
        uint256 _markPrice
    ) private view {
        (uint16 underlyingAssetIndex,, Utils.Strategy strategy,,,,,) = Utils.parseOptionTokenId(_optionTokenId);
        (, bool isOpenPosition) = IPositionManager(positionManager).getPositionRequestInfo(_requestIndex);
        bool isBuy = Utils.isBuy(strategy);
        if (isOpenPosition && isBuy) require(_markPrice >= minMarkPrices[underlyingAssetIndex], "VaultPriceFeed: mark price is too low");
    }
}
