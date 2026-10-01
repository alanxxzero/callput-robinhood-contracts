// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IVault.sol";
import "./interfaces/IOptionsMarket.sol";
import "./interfaces/ISettleManager.sol";
import "./tokens/interfaces/IUSDG.sol";
import "./tokens/interfaces/IERC20.sol";
import "./tokens/libraries/SafeERC20.sol";
import "./tokens/erc1155/interfaces/IERC1155Base.sol";
import "./tokens/erc1155/interfaces/IERC1155Receiver.sol";
import "./oracles/interfaces/IVaultPriceFeed.sol";
import "./AuthorityUtil.sol";
import "./proxy/OwnableUpgradeable.sol";
import "./proxy/ReentrancyGuardUpgradeable.sol";

contract Vault is IVault, IERC1155Receiver, OwnableUpgradeable, ReentrancyGuardUpgradeable, AuthorityUtil {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 100_00;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant USDG_DECIMALS = 18;
    
    bool public override isPositionEnabled;
    // @desc Flag to enable/disable buy olp, sell olp, and swap assets
    bool public override isBuySellSwapEnabled;
    bool public useSwapPricing;
    
    IVaultUtils public override vaultUtils;

    address public override optionsMarket;
    address public override settleManager;
    address public override controller;
    address public override vaultPriceFeed;
    address public override usdg;
    
    uint40 public override thresholdDays;

    // Token Registration
    uint256 public override whitelistedTokenCount;
    uint256 public override totalTokenWeights;

    // Token Registration
    address[] public whitelistedTokens; // even if cleared, the token will remain in this array (so different from whitelistedTokenCount)

    // OLPManager, PositionManager, Controller
    mapping (address => bool) public override isManager; 

    // Token Registration
    mapping (address => bool) public override isWhitelistedToken;
    mapping (address => bool) public override isUnderlyingAssetToken;
    mapping (address => bool) public override isStableToken;
    mapping (address => uint256) public override tokenDecimals;
    mapping (address => uint256) public override tokenBalances; // tokenBalances is used only to determine _transferIn values
    mapping (address => uint256) public override tokenWeights; // tokenWeights allows customisation of index composition

    mapping (address => uint256) public override usdgAmounts; // usdgAmounts tracks the amount of USDG debt for each whitelisted token
    mapping (address => uint256) public override maxUsdgAmounts; // maxUsdgAmounts allows setting a max amount of USDG debt for a token

    // poolAmounts tracks the number of received tokens that can be used for leverage
    // this is tracked separately from tokenBalances to exclude funds that are deposited as margin collateral
    mapping (address => uint256) public override poolAmounts;
    mapping (address => uint256) public override reservedAmounts; // reservedAmounts tracks the number of all tokens reserved for open positions
    mapping (address => uint256) public override utilizedAmounts; // utilizedAmounts tracks the number of OLP's tokens reserved for open positions
    mapping (address => uint256) public override pendingMpAmounts; // pendingMpAmounts tracks the number of mark price
    mapping (address => uint256) public override pendingRpAmounts; // pendingRpAmounts tracks the number of risk premium
    
    // bufferAmounts allows specification of an amount to exclude from swaps
    // this can be used to ensure a certain amount of liquidity is available for leverage positions
    // WBTC = 250000000000
    // WETH = 60000000000000000000000
    mapping (address => uint256) public override bufferAmounts;
    mapping (address => uint256) public override feeReserves; // feeReserves tracks the amount of fees per token
    // decreaseToleranceAmount prevents from revert due to rounding error when decreasing reservedAmounts and utilizedAmounts
    // WBTC = 20000
    // WETH = 4000000000000000
    // USDC = 10000000
    mapping (address => uint256) public override decreaseToleranceAmount; 

    event BuyUSDG(address indexed account, address token, uint256 tokenAmount, uint256 usdgAmount, uint256 feeBasisPoints);
    event SellUSDG(address indexed account, address token, uint256 usdgAmount, uint256 tokenAmount, uint256 feeBasisPoints);
    event Swap(address indexed account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 amountOutAfterFees, uint256 feeBasisPoints);

    event CollectFees(address indexed token, uint256 feeUsd, uint256 feeAmount);
    event CollectPositionFees(address indexed account, address indexed token, uint256 feeUsd, uint256 feeAmount, bool indexed isSettle);

    event DirectPoolDeposit(address indexed token, uint256 amount);
    event IncreasePoolAmount(address indexed token, uint256 amount);
    event DecreasePoolAmount(address indexed token, uint256 amount);
    event IncreaseUsdgAmount(address indexed token, uint256 amount);
    event DecreaseUsdgAmount(address indexed token, uint256 amount);
    event IncreaseReservedAmount(address indexed token, uint256 amount);
    event DecreaseReservedAmount(address indexed token, uint256 amount);
    event IncreaseUtilizedAmount(address indexed token, uint256 amount);
    event DecreaseUtilizedAmount(address indexed token, uint256 amount);

    event FeeRebate(
        address indexed from,
        address indexed to,
        address token,
        uint256 feeRebateAmount,
        uint256 feeAmount,
        uint256 afterFeePaidAmount,
        uint256 tokenSpotPrice,
        address indexed underlyingAsset,
        uint256 size,
        uint256 price,
        bool isSettle,
        bool isCopyTrade
    );

    error AvailableAmountsExceeded();
    error BufferExceeded();
    error Forbidden();
    error NotEnabled();
    error InvalidAmountOrSize();
    error InvalidMarkPrice();
    error InvalidTokenOrAsset();
    error IsNotSellStrategy();
    error PoolAmountExceeded();
    error ReleaseAmountExceeded();
    error UsdgAmountExceeded();
    error UtilizedAmountExceeded();
    error ZeroAddress();

    function initialize(
        uint40 _thresholdDays,
        IOptionsAuthority _authority
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __AuthorityUtil_init__(_authority);

        isBuySellSwapEnabled = true;
        isPositionEnabled = true;
        thresholdDays = _thresholdDays;
    }

    function onlyManager() private view {
        if (!isManager[msg.sender]) { revert Forbidden(); }
    }

    function setManager(address _manager, bool _isManager) external override onlyAdmin {
        isManager[_manager] = _isManager;
    }

    //////////////////////////////////////////////
    //  Setters                                 //
    //////////////////////////////////////////////

    function setIsPositionEnabled(bool _isPositionEnabled) external override onlyAdmin {
        isPositionEnabled = _isPositionEnabled;
    }
    
    function setIsBuySellSwapEnabled(bool _isBuySellSwapEnabled) external override onlyAdmin {
        isBuySellSwapEnabled = _isBuySellSwapEnabled;
    }

    function setThresholdDays(uint40 _thresholdDays) external onlyAdmin {
        thresholdDays = _thresholdDays;
    }

    function setBufferAmount(address _token, uint256 _amount) external override onlyAdmin {
        bufferAmounts[_token] = _amount;
    }

    function setUsdgAmount(address _token, uint256 _amount) external override onlyAdmin {
        uint256 usdgAmount = usdgAmounts[_token];
        uint256 diffAmount;

        if (_amount > usdgAmount) {
            unchecked {
                diffAmount = _amount - usdgAmount;
            }
            _increaseUsdgAmount(_token, diffAmount);
        } else {
            unchecked {
                diffAmount = usdgAmount - _amount;
            }
            _decreaseUsdgAmount(_token, diffAmount);
        }        
    }

    function setContracts(
        IVaultUtils _vaultUtils,
        address _optionsMarket,
        address _settleManager,
        address _controller,
        address _vaultPriceFeed,
        address _usdg
    ) external override onlyAdmin {
        if (
            _optionsMarket == address(0) ||
            _settleManager == address(0) ||
            _controller == address(0) ||
            _vaultPriceFeed == address(0) ||
            _usdg == address(0)
        ) { revert ZeroAddress(); }

        vaultUtils = _vaultUtils;
        
        optionsMarket = _optionsMarket;
        settleManager = _settleManager;
        controller = _controller;
        vaultPriceFeed = _vaultPriceFeed;
        usdg = _usdg;
    }

    function setTokenConfig(
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _maxUsdgAmount,
        bool _isUnderlyingAssetToken,
        bool _isStableToken,
        uint256 _decreaseToleranceAmount
    ) external onlyAdmin {
        if (!isWhitelistedToken[_token]) { // increment token count for the first time
            whitelistedTokenCount = whitelistedTokenCount + 1;
            whitelistedTokens.push(_token);
        }

        uint256 _totalTokenWeights = totalTokenWeights;
        _totalTokenWeights = _totalTokenWeights - tokenWeights[_token];

        isWhitelistedToken[_token] = true;
        tokenDecimals[_token] = _tokenDecimals;
        tokenWeights[_token] = _tokenWeight;
        maxUsdgAmounts[_token] = _maxUsdgAmount;
        isUnderlyingAssetToken[_token] = _isUnderlyingAssetToken;
        isStableToken[_token] = _isStableToken;
        decreaseToleranceAmount[_token] = _decreaseToleranceAmount;

        totalTokenWeights = _totalTokenWeights + _tokenWeight;
    }

    function clearTokenConfig(address _token) external onlyAdmin {
        if (!isWhitelistedToken[_token]) { revert InvalidTokenOrAsset(); }
        totalTokenWeights = totalTokenWeights - tokenWeights[_token];
        delete isWhitelistedToken[_token];
        whitelistedTokenCount = whitelistedTokenCount - 1;
    }

    // strict usage for emergency recovery
    function emergencyRecovery(
        address _token,
        uint256 _amount,
        address _receiver
    ) external onlyAdmin {
        if (_token == address(0)) {
            payable(_receiver).transfer(_amount);
        } else {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }
    }

    // deposit into the pool without minting USDG tokens
    // useful in allowing the pool to become over-collaterised
    function directPoolDeposit(address _token) external override nonReentrant {
        _validateEnabledToken(_token);
        uint256 tokenAmount = _transferIn(_token);
        if (tokenAmount == 0) { revert InvalidAmountOrSize(); }
        _increasePoolAmount(_token, tokenAmount);
        emit DirectPoolDeposit(_token, tokenAmount);
    }

    function withdrawFees(address _token, address _receiver) external override onlyFeeDistributor returns (uint256) {
        uint256 amount = feeReserves[_token];
        if(amount == 0) { return 0; }
        feeReserves[_token] = 0;
        _transferOut(_token, amount, _receiver);
        return amount;
    }

    function updatePendingAmount(address _token) public override {
        (uint256 releaseMpAmount, uint256 releaseRpAmount) = vaultUtils.getReleaseAmountAll(_token);
        if (pendingMpAmounts[_token] < releaseMpAmount || pendingRpAmounts[_token] < releaseRpAmount) { revert ReleaseAmountExceeded(); }
        pendingMpAmounts[_token] -= releaseMpAmount;
        pendingRpAmounts[_token] -= releaseRpAmount;
    }

    //////////////////////////////////////////////
    //               Get Functions              //
    //////////////////////////////////////////////

    function whitelistedTokensLength() external override view returns (uint256) {
        return whitelistedTokens.length;
    }

    function getSpotPrice(address _token, bool _maximise) public override view returns (uint256) {
        return IVaultPriceFeed(vaultPriceFeed).getSpotPrice(_token, _maximise);    
    }

    function getSettlePrice(address _tokenAddress, uint256 _expiry) public override view returns (uint256) {
        return IVaultPriceFeed(vaultPriceFeed).getSettlePrice(_tokenAddress, _expiry);
    }

    function getTargetUsdgAmount(address _token) public override view returns (uint256) {
        uint256 supply = IERC20(usdg).totalSupply();
        if (supply == 0) { return 0; }
        uint256 weight = tokenWeights[_token];
        return ((weight * supply) / totalTokenWeights);
    }

    function getRedemptionAmount(address _token, uint256 _usdgAmount) public override view returns (uint256) {
        uint256 price = getSpotPrice(_token, true);
        uint256 redemptionAmount = (_usdgAmount * PRICE_PRECISION) / price;
        return adjustForDecimals(redemptionAmount, usdg, _token);
    }

    function getMainStableAsset() public override view returns (address) {
        (address mainStableAsset, uint decimal) = IOptionsMarket(optionsMarket).getMainStableAsset();
        if (!isWhitelistedToken[mainStableAsset] || !isStableToken[mainStableAsset]) { revert InvalidTokenOrAsset(); }
        if (decimal != tokenDecimals[mainStableAsset]) { revert InvalidTokenOrAsset(); }
        return mainStableAsset;
    }

    function getUnderlyingAssetByIndex(uint16 _underlyingAssetIndex) public override view returns (address) {
        (address underlyingAsset, uint decimal) = IOptionsMarket(optionsMarket).getUnderlyingAssetByIndex(_underlyingAssetIndex);
        if (!isWhitelistedToken[underlyingAsset] || !isUnderlyingAssetToken[underlyingAsset]) { revert InvalidTokenOrAsset(); }
        if (decimal != tokenDecimals[underlyingAsset]) { revert InvalidTokenOrAsset(); }
        return underlyingAsset;
    }


    //////////////////////////////////////////////
    //            OlpManager Related            //
    //////////////////////////////////////////////
    
    function buyUSDG(address _token, address _receiver) external override nonReentrant returns (uint256) {
        onlyManager();

        if (!isBuySellSwapEnabled) { revert NotEnabled(); }
        _validateEnabledToken(_token);

        updatePendingAmount(_token);

        uint256 tokenAmount = _transferIn(_token);
        if (tokenAmount == 0) { revert InvalidAmountOrSize(); }

        uint256 price = getSpotPrice(_token, false);

        uint256 usdgAmount = (tokenAmount * price) / PRICE_PRECISION;
        usdgAmount = adjustForDecimals(usdgAmount, _token, usdg);
        if (usdgAmount == 0) { revert InvalidAmountOrSize(); }

        uint256 buyUsdgFeeBasisPoints = vaultUtils.getBuyUsdgFeeBasisPoints(_token, usdgAmount);
        uint256 amountAfterFees = _collectFees(_token, tokenAmount, buyUsdgFeeBasisPoints);
        uint256 mintAmount = (amountAfterFees * price) / PRICE_PRECISION;
        mintAmount = adjustForDecimals(mintAmount, _token, usdg);

        _increaseUsdgAmount(_token, mintAmount);
        _increasePoolAmount(_token, amountAfterFees);

        IUSDG(usdg).mint(_receiver, mintAmount);

        emit BuyUSDG(_receiver, _token, tokenAmount, mintAmount, buyUsdgFeeBasisPoints);

        return mintAmount;
    }

    function sellUSDG(address _token, address _receiver) external override nonReentrant returns (uint256) {
        onlyManager();

        if (!isBuySellSwapEnabled) { revert NotEnabled(); }
        _validateEnabledToken(_token);
        
        updatePendingAmount(_token);

        uint256 usdgAmount = _transferIn(usdg);
        if (usdgAmount == 0) { revert InvalidAmountOrSize(); }

        uint256 redemptionAmount = getRedemptionAmount(_token, usdgAmount);
        if (redemptionAmount == 0) { revert InvalidAmountOrSize(); }

        _decreaseUsdgAmount(_token, usdgAmount);
        _decreasePoolAmount(_token, redemptionAmount);

        IUSDG(usdg).burn(address(this), usdgAmount);

        // the _transferIn call increased the value of tokenBalances[usdg]
        // usually decreases in token balances are synced by calling _transferOut
        // however, for usdg, the tokens are burnt, so _updateTokenBalance should
        // be manually called to record the decrease in tokens
        _updateTokenBalance(usdg);

        uint256 sellUsdgFeeBasisPoints = vaultUtils.getSellUsdgFeeBasisPoints(_token, usdgAmount);
        uint256 amountOut = _collectFees(_token, redemptionAmount, sellUsdgFeeBasisPoints);
        if (amountOut == 0) { revert InvalidAmountOrSize(); }

        _transferOut(_token, amountOut, _receiver);

        emit SellUSDG(_receiver, _token, usdgAmount, amountOut, sellUsdgFeeBasisPoints);

        return amountOut;
    }

    // usually called from PositionManager.executeOpenPosition
    // _tokenIn = request.path[0]
    // _tokenOut = request.path[1]
    // _receiver = PositionRouter
    function swap(address _tokenIn, address _tokenOut, address _receiver) external override nonReentrant returns (uint256) {
        onlyManager();

        if (!isBuySellSwapEnabled) { revert NotEnabled(); }
        _validateEnabledToken(_tokenIn);
        _validateEnabledToken(_tokenOut);
        if (_tokenIn == _tokenOut) { revert InvalidTokenOrAsset(); }

        uint256 amountIn = _transferIn(_tokenIn);
        if (amountIn == 0) { revert InvalidAmountOrSize(); }

        uint256 priceIn = getSpotPrice(_tokenIn, false);
        uint256 priceOut = getSpotPrice(_tokenOut, true);

        uint256 amountOut = (amountIn * priceIn) / priceOut;
        amountOut = adjustForDecimals(amountOut, _tokenIn, _tokenOut);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        uint256 usdgAmount = (amountIn * priceIn) / PRICE_PRECISION;
        usdgAmount = adjustForDecimals(usdgAmount, _tokenIn, usdg);

        uint256 swapFeeBasisPoints = vaultUtils.getSwapFeeBasisPoints(_tokenIn, _tokenOut, usdgAmount);

        uint256 amountOutAfterFees = _collectFees(_tokenOut, amountOut, swapFeeBasisPoints);

        _increaseUsdgAmount(_tokenIn, usdgAmount);
        _decreaseUsdgAmount(_tokenOut, usdgAmount);

        _increasePoolAmount(_tokenIn, amountIn);
        _decreasePoolAmount(_tokenOut, amountOut);

        if (poolAmounts[_tokenOut] < bufferAmounts[_tokenOut]) { revert BufferExceeded(); }

        _transferOut(_tokenOut, amountOutAfterFees, _receiver);

        emit Swap(_receiver, _tokenIn, _tokenOut, amountIn, amountOut, amountOutAfterFees, swapFeeBasisPoints);

        return amountOutAfterFees;
    }


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
    ) external override nonReentrant onlyController returns (
        uint256 sizeOut, // sizeOut is the size of the option token
        uint256 executionPrice, // executionPrice is the price at which the option is executed
        address utilizedToken, // (only for buy) utilizedToken is the token reserved by olp
        uint256 utilizedAmount, // (only for buy) utilizedAmount is the amount reserved by olp
        address tokenOut, // (only for sell) tokenOut is the token paid to the trader
        uint256 amountOut, // (only for sell) amountOut is the amount paid to the trader
        uint256 afterFeePaidAmount
    ) {
        if (!isPositionEnabled) { revert NotEnabled(); }
        _validateEnabledToken(_quoteToken);

        bool isBuy = Utils.isBuy(_strategy);
        
        address mainStableAsset = getMainStableAsset();
        address underlyingAsset = getUnderlyingAssetByIndex(_underlyingAssetIndex);
        
        uint256 paidAmount = _transferIn(_quoteToken);
        
        (uint256 markPrice, uint256 riskPremium) = IVaultPriceFeed(vaultPriceFeed).getMarkPriceAndRiskPremium(_optionTokenId, _requestIndex);
        if (!isBuy && markPrice <= riskPremium) { revert InvalidMarkPrice(); }
        executionPrice = isBuy ? markPrice + riskPremium : markPrice - riskPremium;
    
        uint256 estimatedSize = _calculateEstimatedSizeForOpenPosition(
            underlyingAsset,
            _strategy,
            _strikePrices,
            executionPrice,
            _quoteToken,
            paidAmount
        );

        (afterFeePaidAmount, sizeOut) = _collectPositionFees(_account, _strategy, _quoteToken, paidAmount, underlyingAsset, estimatedSize, executionPrice, true, false, _requestIndex);

        // 1. increase poolAmounts by the amount paid by the trader
        // - when the trader is buying, the amount paid is the premium
        // - when the trader is selling, the amount paid is the collateral
        _increasePoolAmount(_quoteToken, afterFeePaidAmount);

        if (isBuy) { // when trader is opening buy, olp is opening sell (pays collateral) (executionPrice = markPrice + riskPremium)
            // first, process with the tokens paid by the trader (option premiums) 
            uint256 rpAmount = afterFeePaidAmount * riskPremium / executionPrice;
            _increasePendingAmount(IVaultUtils.PriceType.RP, _quoteToken, rpAmount);
            _increasePendingAmount(IVaultUtils.PriceType.MP, _quoteToken, afterFeePaidAmount - rpAmount);

            // calculate collateral to pay (sell)
            Utils.Strategy oppositeStrategy = Utils.getOppositeStrategy(_strategy);
            utilizedToken = oppositeStrategy == Utils.Strategy.SellCall ? underlyingAsset : mainStableAsset;
            
            uint256 utilizedAmountPerSize = _calculateCollateralAmountPerSize(underlyingAsset, oppositeStrategy, _strikePrices);
            utilizedAmount = utilizedAmountPerSize * sizeOut / (10 ** tokenDecimals[underlyingAsset]);

            _increaseReservedAmount(utilizedToken, utilizedAmount);
            _increaseUtilizedAmount(utilizedToken, utilizedAmount);
        } else { // when trader is opening sell, olp is opening buy (pays premium to trader) (executionPrice = markPrice - riskPremium)
            // first process with the tokens paid by the trader (collateral)
            _increaseReservedAmount(_quoteToken, afterFeePaidAmount);
            
            // calculate option premiums to pay to the trader (execution price = mark price - risk premium)
            uint256 payoutAmountUsd = sizeOut * executionPrice / (10 ** tokenDecimals[underlyingAsset]); // decimal 30

            tokenOut = mainStableAsset;
            amountOut = usdToToken(tokenOut, payoutAmountUsd, false);

            _decreasePoolAmount(tokenOut, amountOut);
            _transferOut(tokenOut, amountOut, _receiver);

            uint256 rpUsd = sizeOut * riskPremium / (10 ** tokenDecimals[underlyingAsset]);
            uint256 rpAmount = usdToToken(mainStableAsset, rpUsd, true);
            _increasePendingAmount(IVaultUtils.PriceType.RP, mainStableAsset, rpAmount);
        }
    }

    function closePosition(
        address _account,
        uint256 _requestIndex,
        uint256 _optionTokenId,
        uint256 _size,
        uint16 _underlyingAssetIndex,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        address _quoteToken, // when closing buy position, quoteToken is mainStableAsset, when closing sell position, quoteToken is usdc except sell call
        address _receiver
    ) external override nonReentrant onlyController returns (
        uint256 executionPrice, // executionPrice is the price at which the option is executed
        uint256 amountOut, // amountOut is the amount paid to the trader (for buy, it's the premium) (for sell, it's the collateral - premium)
        uint256 totalExecutionPriceAmount, // option premiums (for buy case, totalExecutionPriceAmount = amountOut + feeAmount)
        uint256 utilizedAmount // (only for sell) utilizedAmount is the amount reserved by olp
    ) {
        if (!isPositionEnabled) { revert NotEnabled(); }
        _validateEnabledToken(_quoteToken);

        bool isBuy = Utils.isBuy(_strategy);

        address underlyingAsset = getUnderlyingAssetByIndex(_underlyingAssetIndex);
        
        (uint256 markPrice, uint256 riskPremium) = IVaultPriceFeed(vaultPriceFeed).getMarkPriceAndRiskPremium(_optionTokenId, _requestIndex);
        if (isBuy && markPrice <= riskPremium) { revert InvalidMarkPrice(); }
        executionPrice = isBuy ? markPrice - riskPremium : markPrice + riskPremium;

        uint256 totalExecutionPrice = executionPrice * _size / (10 ** tokenDecimals[underlyingAsset]);
        totalExecutionPriceAmount = isBuy 
            ? usdToToken(_quoteToken, totalExecutionPrice, false) // option premiums to pay to trader (buyCall, buyPut, buyCallSpread, buyPutSpread => quoteToken = mainStableAsset)
            : usdToToken(_quoteToken, totalExecutionPrice, true); // option premiums to receive from trader (sellCall => quoteToken = underlyingAsset / sellPut, sellCallSpread, sellPutSpread => quoteToken = mainStableAsset)
        
        uint256 payoutAmount;

        if (isBuy) { // executionPrice = markPrice - riskPremium
            payoutAmount = totalExecutionPriceAmount;
            
            uint256 rpUsd = _size * riskPremium / (10 ** tokenDecimals[underlyingAsset]);
            uint256 rpAmount = usdToToken(_quoteToken, rpUsd, true);
            _increasePendingAmount(IVaultUtils.PriceType.RP, _quoteToken, rpAmount);
        } else { // executionPrice = markPrice + riskPremium 
            uint256 collateralAmountPerSize = _calculateCollateralAmountPerSize(underlyingAsset, _strategy, _strikePrices);
            utilizedAmount = collateralAmountPerSize * _size  / (10 ** tokenDecimals[underlyingAsset]);
            payoutAmount = utilizedAmount - totalExecutionPriceAmount;

            uint256 rpAmount = totalExecutionPriceAmount * riskPremium / executionPrice;
            _increasePendingAmount(IVaultUtils.PriceType.RP, _quoteToken, rpAmount);
            _increasePendingAmount(IVaultUtils.PriceType.MP, _quoteToken, totalExecutionPriceAmount - rpAmount);
            
            _increaseUtilizedAmount(_quoteToken, utilizedAmount);
        }

        // decrease poolAmounts by the amount of tokens to pay to the trader
        // - when the trader is closing a buy position, the amount paid is the premium
        // - when the trader is closing a sell position, the amount paid is the collateral - premium
        // - the collateral of sell call is the underlying asset, others are mainStableAsset
        _decreasePoolAmount(_quoteToken, payoutAmount);

        (amountOut, ) = _collectPositionFees(_account, _strategy, _quoteToken, payoutAmount, underlyingAsset, _size, executionPrice, false, false, _requestIndex);
        _transferOut(_quoteToken, amountOut, _receiver);
    }

    function settlePosition(
        address _account,
        uint256 _size,
        uint16 _underlyingAssetIndex,
        uint40 _expiry,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        bool _isAccountVault,
        address _quoteToken,
        address _receiver
    ) public override nonReentrant onlyController returns (
        uint256 settlePrice, // settlePrice is the price at which the option is settled
        uint256 amountOut, // amountOut is the amount paid to the trader (for buy, it's the intrinsic) (for sell, it's the collateral - intrinsic)
        uint256 totalIntrinsicAmount // total settle payoff (for buy, totalIntrinsicAmount = amountOut + feeAmount)
    ) {
        if (!isPositionEnabled) { revert NotEnabled(); }
        _validateEnabledToken(_quoteToken);

        updatePendingAmount(_quoteToken);

        bool isBuy = Utils.isBuy(_strategy);

        address mainStableAsset = getMainStableAsset();
        address underlyingAsset = getUnderlyingAssetByIndex(_underlyingAssetIndex);

        settlePrice = getSettlePrice(underlyingAsset, _expiry);

        (bool isItm, uint256 intrinsicUsd) = vaultUtils.calculateItmStatusAndIntrinsicUsd(_strategy, _strikePrices, settlePrice);

        uint256 totalIntrinsicUsd = intrinsicUsd * _size  / (10 ** tokenDecimals[underlyingAsset]);
        totalIntrinsicAmount = isBuy
            ? usdToToken(_quoteToken, totalIntrinsicUsd, false)
            : usdToToken(_quoteToken, totalIntrinsicUsd, true);

        uint256 payoutAmount;

        if (isBuy) {
            if (isItm) {
                payoutAmount = totalIntrinsicAmount;
            }
        } else {
            address collateralToken = _strategy == Utils.Strategy.SellCall ? underlyingAsset : mainStableAsset;
            uint256 collateralAmountPerSize = _calculateCollateralAmountPerSize(underlyingAsset, _strategy, _strikePrices);
            uint256 collateralAmount = collateralAmountPerSize * _size / (10 ** tokenDecimals[underlyingAsset]);
            
            _decreaseReservedAmount(collateralToken, collateralAmount);

            if (_isAccountVault) _decreaseUtilizedAmount(collateralToken, collateralAmount);

            if (isItm) {
                payoutAmount = collateralAmount - totalIntrinsicAmount;
            } else {
                payoutAmount = collateralAmount;
            }
        }

        _decreasePoolAmount(_quoteToken, payoutAmount); // decrease poolAmounts by both the payout and fee amounts

        if (isItm) {
            (amountOut,) = _collectPositionFees(_account, _strategy, _quoteToken, payoutAmount, underlyingAsset, _size, settlePrice, false, true, 0);
        } else {
            amountOut = payoutAmount;
        }
        
        _transferOut(_quoteToken, amountOut, _receiver);
    }

    function clearPosition(
        uint256 _size,
        uint16 _underlyingAssetIndex,
        Utils.Strategy _strategy, // allow only sell strategy
        uint48[4] memory _strikePrices
    ) external override nonReentrant onlyController {
        if (Utils.isBuy(_strategy)) { revert IsNotSellStrategy(); }
        
        address mainStableAsset = getMainStableAsset();
        address underlyingAsset = getUnderlyingAssetByIndex(_underlyingAssetIndex);

        address collateralToken = _strategy == Utils.Strategy.SellCall ? underlyingAsset : mainStableAsset;
        uint256 collateralAmountPerSize = _calculateCollateralAmountPerSize(underlyingAsset, _strategy, _strikePrices);
        uint256 collateralAmount = collateralAmountPerSize * _size / (10 ** tokenDecimals[underlyingAsset]);

        _decreaseReservedAmount(collateralToken, collateralAmount);
        _decreaseUtilizedAmount(collateralToken, collateralAmount);
    }

    function settleVaultPosition(
        address[] memory _path,
        uint16 _underlyingAssetIndex,
        uint256 _optionTokenId
    ) external override returns (uint256) {
        if (msg.sender != address(vaultUtils)) { revert Forbidden(); }

        uint256 amountOut = ISettleManager(settleManager).settlePosition(
            _path,
            _underlyingAssetIndex,
            _optionTokenId,
            0,
            false
        );

        return amountOut;
    }


    //////////////////////////////////////////////
    //             Utility Functions            //
    //////////////////////////////////////////////

    function adjustForDecimals(uint256 _amount, address _tokenDiv, address _tokenMul) public view returns (uint256) {
        uint256 decimalsDiv = _tokenDiv == usdg ? USDG_DECIMALS : tokenDecimals[_tokenDiv];
        uint256 decimalsMul = _tokenMul == usdg ? USDG_DECIMALS : tokenDecimals[_tokenMul];
        return (_amount * (10 ** decimalsMul)) / (10 ** decimalsDiv);
    }

    function tokenToUsdMin(address _token, uint256 _tokenAmount) public override view returns (uint256) {
        if (_tokenAmount == 0) { return 0; }
        uint256 price = getSpotPrice(_token, false);
        uint256 decimals = tokenDecimals[_token];
        return ((_tokenAmount * price) / (10 ** decimals)); // decimal 30
    }

    // _maximise is true means price is minimum, token amount is maximum
    // _maximise is false means price is maximum, token amount is minimum
    function usdToToken(address _token, uint256 _usdAmount, bool _maximise) public override view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        uint256 price = getSpotPrice(_token, !_maximise);
        uint256 decimals = tokenDecimals[_token];
        return ((_usdAmount * (10 ** decimals)) / price);
    }

    function isEnabledToken(address _token) public override view returns (bool) {
        return isWhitelistedToken[_token] && maxUsdgAmounts[_token] > 0;
    }

    //////////////////////////////////////////////
    //            Internal Functions            //
    //////////////////////////////////////////////

    // the decimals of size is the same as the decimals of underlyingAsset
    function _calculateEstimatedSizeForOpenPosition(
        address _underlyingAsset,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        uint256 _executionPrice,
        address _token,
        uint256 _amount
    ) internal view returns (uint256 estimatedSize) {
        if (Utils.isBuy(_strategy)) {
            uint256 paidUsd = tokenToUsdMin(_token, _amount);
            estimatedSize = paidUsd * (10 ** tokenDecimals[_underlyingAsset]) / _executionPrice;
        }
        
        else {
            uint256 collateralAmountPerSize = _calculateCollateralAmountPerSize(_underlyingAsset, _strategy, _strikePrices);

            // SellCall, the _amount and collateralAmount are based on the underlyingAsset
            // SellPut, SellCallSpread, SellPutSpread, the _amount and collateralAmount are based on the mainStableAsset
            estimatedSize = _amount * (10 ** tokenDecimals[_underlyingAsset]) / collateralAmountPerSize;
        }

        if (estimatedSize == 0) { revert InvalidAmountOrSize(); }
    }

    function _calculateCollateralAmountPerSize(
        address _underlyingAsset,
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices
    ) internal view returns (uint256) {
        if (Utils.isBuy(_strategy)) { revert IsNotSellStrategy(); }

        if (_strategy == Utils.Strategy.SellCall) {
            return 10 ** tokenDecimals[_underlyingAsset];
        }

        address mainStableAsset = getMainStableAsset(); 

        uint256 collateralUsd;

        if (_strategy == Utils.Strategy.SellPut) {
            collateralUsd = _strikePrices[0] * PRICE_PRECISION;
        }
        
        if (_strategy == Utils.Strategy.SellCallSpread || _strategy == Utils.Strategy.SellPutSpread) {
            collateralUsd = (_strikePrices[1] - _strikePrices[0]) * PRICE_PRECISION;
        }

        return usdToToken(mainStableAsset, collateralUsd, true);
    }

    function _collectFees(address _token, uint256 _amount, uint256 _feeBasisPoints) private returns (uint256) {
        uint256 feeAmount = _applyPercentage(_amount, _feeBasisPoints);
        
        feeReserves[_token] = feeReserves[_token] + feeAmount;
        emit CollectFees(_token, tokenToUsdMin(_token, feeAmount), feeAmount);
        
        return _amount - feeAmount;
    }

    function _collectPositionFees(
        address _account,
        Utils.Strategy _strategy,
        address _token,
        uint256 _amount,
        address _underlyingAsset,
        uint256 _size,
        uint256 _price, // execution price or settle price
        bool _isOpen,
        bool _isSettle,
        uint256 _requestIndex
    ) private returns (uint256, uint256) {
        (uint256 afterFeePaidAmount, uint256 size, uint256 feeUsd, uint256 feeAmount, address rebateReceiver, uint256 feeRebateRate, bool isCopyTrade) = vaultUtils.getPositionFeeInfo(
            _account,
            _strategy,
            _token,
            _amount,
            _underlyingAsset,
            _size,
            _price,
            _isOpen,
            _isSettle,
            _requestIndex
        );
        
        if (feeRebateRate > 0) {
            uint256 feeRebateAmount = _applyPercentage(feeAmount, feeRebateRate);
            uint256 feeRebateUsd = tokenToUsdMin(_token, feeRebateAmount);
            _transferOut(_token, feeRebateAmount, rebateReceiver);

            feeAmount = feeAmount - feeRebateAmount;
            feeUsd = feeUsd - feeRebateUsd;

            emit FeeRebate(
                _account,
                rebateReceiver,
                _token,
                feeRebateAmount,
                feeAmount,
                afterFeePaidAmount,
                getSpotPrice(_token, false),
                _underlyingAsset,
                size,
                _price,
                _isSettle,
                isCopyTrade
            );
        }
        
        feeReserves[_token] = feeReserves[_token] + feeAmount;
        emit CollectPositionFees(_account, _token, feeUsd, feeAmount, _isSettle);

        return (afterFeePaidAmount, size);
    }

    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
        return (nextBalance - prevBalance);
    }

    function _transferOut(address _token, uint256 _amount, address _receiver) private {
        IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
    }

    function _updateTokenBalance(address _token) private {
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
    }

    function _increasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] = poolAmounts[_token] + _amount;
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (poolAmounts[_token] > balance) { revert PoolAmountExceeded(); }
        emit IncreasePoolAmount(_token, _amount);
    }

    function _decreasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] = poolAmounts[_token] - _amount;
        if (reservedAmounts[_token] + pendingMpAmounts[_token] + pendingRpAmounts[_token] > poolAmounts[_token]) { revert AvailableAmountsExceeded(); }
        emit DecreasePoolAmount(_token, _amount);
    }

    function _increaseUsdgAmount(address _token, uint256 _amount) private {
        usdgAmounts[_token] = usdgAmounts[_token] + _amount;
        uint256 maxUsdgAmount = maxUsdgAmounts[_token];
        if (usdgAmounts[_token] > maxUsdgAmount) { revert UsdgAmountExceeded(); }
        emit IncreaseUsdgAmount(_token, _amount);
    }

    function _decreaseUsdgAmount(address _token, uint256 _amount) private {
        uint256 currentAmount = usdgAmounts[_token];
        uint256 decreaseAmount = _amount >= currentAmount ? currentAmount : _amount;
        unchecked {
            usdgAmounts[_token] = currentAmount - decreaseAmount;
        }
        emit DecreaseUsdgAmount(_token, decreaseAmount);
    }

    function _increaseReservedAmount(address _token, uint256 _amount) private {
        reservedAmounts[_token] = reservedAmounts[_token] + _amount;
        if (reservedAmounts[_token] + pendingMpAmounts[_token] + pendingRpAmounts[_token] > poolAmounts[_token]) { revert AvailableAmountsExceeded(); }
        emit IncreaseReservedAmount(_token, _amount);
    }

    function _decreaseReservedAmount(address _token, uint256 _amount) private {
        uint256 currentAmount = reservedAmounts[_token];
        uint256 buffer = decreaseToleranceAmount[_token];

        if (currentAmount + buffer < _amount) { revert BufferExceeded(); }

        uint256 decreaseAmount = _amount >= currentAmount ? currentAmount : _amount;
        unchecked {
            reservedAmounts[_token] = currentAmount - decreaseAmount;
        }
        emit DecreaseReservedAmount(_token, decreaseAmount);
    }

    function _increaseUtilizedAmount(address _token, uint256 _amount) private {
        utilizedAmounts[_token] = utilizedAmounts[_token] + _amount;
        if (utilizedAmounts[_token] > reservedAmounts[_token]) { revert UtilizedAmountExceeded(); }
        emit IncreaseUtilizedAmount(_token, _amount);
    }

    function _decreaseUtilizedAmount(address _token, uint256 _amount) private {
        uint256 currentAmount = utilizedAmounts[_token];
        uint256 buffer = decreaseToleranceAmount[_token];

        if (currentAmount + buffer < _amount) { revert BufferExceeded(); }

        uint256 decreaseAmount = _amount >= currentAmount ? currentAmount : _amount;
        unchecked {
            utilizedAmounts[_token] = currentAmount - decreaseAmount;
        }
        emit DecreaseUtilizedAmount(_token, decreaseAmount);
    }

    function _increasePendingAmount(IVaultUtils.PriceType _priceType, address _token, uint256 _pendingAmount) internal {
        if (poolAmounts[_token] - reservedAmounts[_token] - pendingMpAmounts[_token] - pendingRpAmounts[_token] < _pendingAmount) { revert AvailableAmountsExceeded(); }
        vaultUtils.notifyPendingAmount(_priceType, _token, tokenToUsdMin(_token, _pendingAmount), _pendingAmount);
        
        if (_priceType == IVaultUtils.PriceType.MP) {
            pendingMpAmounts[_token] += _pendingAmount;
        } else {
            pendingRpAmounts[_token] += _pendingAmount;
        }

        updatePendingAmount(_token);
    }

    function _applyPercentage(uint256 _baseAmount, uint256 _basisPoints) private pure returns (uint256) {
        return (_baseAmount * _basisPoints) / BASIS_POINTS_DIVISOR;
    }
    
    function _validateEnabledToken(address _token) internal view {        
        if (!isWhitelistedToken[_token]) { revert InvalidTokenOrAsset(); }
        if (maxUsdgAmounts[_token] == 0) { revert NotEnabled(); }
    }

    //////////////////////////////////////////////
    //              NFT Interfaces              //
    //////////////////////////////////////////////

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address operator, address from, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
