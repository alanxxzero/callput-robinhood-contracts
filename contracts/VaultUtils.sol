// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IPositionManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./tokens/interfaces/IERC20.sol";
import "./peripherals/interfaces/IReferral.sol";

import "./AuthorityUtil.sol";

import "./proxy/OwnableUpgradeable.sol";

contract VaultUtils is IVaultUtils, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant BASIS_POINTS_DIVISOR = 100_00; // 100%
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MAX_FEE = 500; // 5% - maximum fee limit

    address public vault;
    address public referral;
    
    bool public override hasDynamicFees;

    uint256[] public selfOriginExpiries;
    uint256[] public selfOriginExpiriesToSettle; // When self-originated expiry is ready to be settled, it migrated from selfOriginExpiries to this array
    uint256[] public externalOriginExpiries; // @desc deprecated
    uint256[] public externalOriginExpiriesToSettle; // @desc deprecated
    
    mapping(uint256 => bool) public override isSelfExpiryAdded; // when pushing expiry to expiries, set true
    mapping(uint256 => bool) public isExternalExpiryAdded; // @desc deprecated
    
    mapping(uint256 => uint256) public selfExpiryIndex;
    mapping(uint256 => uint256) public externalExpiryIndex; // @desc deprecated
    mapping(uint256 => uint256) public selfExpiryToSettleIndex;
    mapping(uint256 => uint256) public externalExpiryToSettleIndex; // @desc deprecated

    mapping(IVaultUtils.FeeType => uint256) public feeBasisPoints; // @desc deprecated

    mapping(uint256 => OptionToken[]) public optionTokensAtSelfExpiry; // expiry => OptionToken[]
    mapping(uint256 => OptionToken[]) public optionTokensAtExternalExpiry; // @desc deprecated
    
    mapping(uint256 => bool) public override isPositionAtSelfExpirySettled; // when vault's positions are settled at expiry, set true
    mapping(uint256 => bool) public isPositionAtExternalExpirySettled; // @desc deprecated

    mapping(uint256 => uint256) public override optionTokensAtSelfExpiryStart; // expiry => optionTokensAtSelfExpiry start index (need when settle vault's positions)
    mapping(uint256 => uint256) public optionTokensAtExternalExpiryStart; // @desc deprecated

    mapping(PriceType => mapping(address => uint256)) public override releaseRate; // releaseRate = pendingAmount / releaseDuration
    mapping(PriceType => mapping(address => uint256)) public releaseDuration;
    mapping(PriceType => mapping(address => uint256)) public override periodFinish;
    mapping(PriceType => mapping(address => uint256)) public lastReleasedTime;
    mapping(PriceType => mapping(address => uint256)) public lastUpdateTime;

    uint256 public tradeFeeCalculationLimitRate;
    uint256 public settleFeeCalculationLimitRate;

    address public positionManager;

    // Fee Basis Points (configurable) - added at the end to preserve storage layout
    uint256 public OPEN_BUY_NAKED_POSITION_FEE;
    uint256 public OPEN_SELL_NAKED_POSITION_FEE;
    uint256 public OPEN_COMBO_POSITION_FEE;
    uint256 public CLOSE_NAKED_POSITION_FEE;
    uint256 public CLOSE_COMBO_POSITION_FEE;
    uint256 public SETTLE_POSITION_FEE;
    uint256 public TAX_FEE;
    uint256 public STABLE_TAX_FEE;
    uint256 public MINT_BURN_FEE;
    uint256 public SWAP_FEE;
    uint256 public STABLE_SWAP_FEE;

    event SetHasDynamicFees(bool hasDynamicFees);
    event SetTradeFeeCalculationLimitRate(uint256 tradeFeeCalculationLimitRate);
    event SetSettleFeeCalculationLimitRate(uint256 settleFeeCalculationLimitRate);
    event SetReferral(address indexed referral);
    event SetReleaseDuration(address indexed token, uint256 releaseDuration, PriceType indexed priceType);
    event SetFee(string feeName, uint256 oldValue, uint256 newValue);
    event VaultPositionSettled(address indexed vault, uint256 indexed expiry);
    event VaultPendingPositionSettled(address indexed vault, uint256 indexed expiry);
    event NotifyPendingAmount(PriceType indexed priceType, address indexed token, uint256 pendingUsd, uint256 pendingAmount);

    error AlreadySettled();
    error Forbidden();
    error InsufficientAmountOrSize();
    error LimitExceeded();
    error NotFound();
    error ZeroAddress();

    function initialize(
        address _vault,
        IOptionsAuthority _authority
    ) external initializer {
        if (_vault == address(0)) { revert ZeroAddress(); }
        
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        vault = _vault;

        OPEN_BUY_NAKED_POSITION_FEE = 6; // 0.06%
        OPEN_SELL_NAKED_POSITION_FEE = 3; // 0.03%
        OPEN_COMBO_POSITION_FEE = 3; // 0.03%
        CLOSE_NAKED_POSITION_FEE = 3; // 0.03%
        CLOSE_COMBO_POSITION_FEE = 3; // 0.03%
        SETTLE_POSITION_FEE = 2; // 0.02%
        TAX_FEE = 60; // 0.6%
        STABLE_TAX_FEE = 5; // 0.05%
        MINT_BURN_FEE = 25; // 0.25%
        SWAP_FEE = 25; // 0.25%
        STABLE_SWAP_FEE = 1; // 0.01%
    }

    modifier onlyVault() {
        if (msg.sender != vault) { revert Forbidden(); }
        _;
    }

    function setPositionManager(address _positionManager) external onlyAdmin {
        if (_positionManager == address(0)) { revert ZeroAddress(); }
        positionManager = _positionManager;
    }

    //////////////////////////////////////////////
    //  General Util Functions                  //
    //////////////////////////////////////////////

    // as whitelistedTokens array of vault has non whitelisted tokens, we need to filter them
    function getWhitelistedTokens() public override view returns (address[] memory) {
        uint256 length = IVault(vault).whitelistedTokensLength();
        address[] memory whitelistedTokens = new address[](length);

        uint256 counter = 0;        

        for (uint256 i = 0; i < length;) {
            address token = IVault(vault).whitelistedTokens(i);
            bool isWhitelisted = IVault(vault).isWhitelistedToken(token);

            if (isWhitelisted) {
                whitelistedTokens[counter] = token;
                counter++;
            }

            unchecked { i++; }
        }

        assembly {
            mstore(whitelistedTokens, counter)
        }

        return whitelistedTokens;
    }

    function getEnabledTokens() public override view returns (address[] memory) {
        uint256 length = IVault(vault).whitelistedTokensLength();
        address[] memory enabledTokens = new address[](length);

        uint256 counter = 0;

        for (uint256 i = 0; i < length;) {
            address token = IVault(vault).whitelistedTokens(i);
            bool isEnabled = IVault(vault).isEnabledToken(token);

            if (isEnabled) {
                enabledTokens[counter] = token;
                counter++;
            }

            unchecked { i++; }
        }

        assembly {
            mstore(enabledTokens, counter)
        }

        return enabledTokens;
    }

    function calculateItmStatusAndIntrinsicUsd(
        Utils.Strategy _strategy,
        uint48[4] memory _strikePrices,
        uint256 _settlePrice
    ) external override pure returns (bool isItm, uint256 intrinsicUsd) {
        uint256[4] memory strikePricesWithPrecision = [
            _strikePrices[0] * PRICE_PRECISION,
            _strikePrices[1] * PRICE_PRECISION,
            _strikePrices[2] * PRICE_PRECISION,
            _strikePrices[3] * PRICE_PRECISION
        ];

        bool isNakedCall = Utils.isNaked(_strategy) && Utils.isCall(_strategy);
        bool isNakedPut = Utils.isNaked(_strategy) && Utils.isPut(_strategy);
        bool isCallSpread = Utils.isSpread(_strategy) && Utils.isCall(_strategy);
        bool isPutSpread = Utils.isSpread(_strategy) && Utils.isPut(_strategy);

        isItm = false;
        intrinsicUsd = 0;
        
        if (isNakedCall && strikePricesWithPrecision[0] < _settlePrice) {
            isItm = true;
            unchecked {
                intrinsicUsd = _settlePrice - strikePricesWithPrecision[0];
            }
        }
        
        else if (isCallSpread && strikePricesWithPrecision[0] < _settlePrice) {
            isItm = true;
            unchecked {
                intrinsicUsd = _settlePrice - strikePricesWithPrecision[0];
            }
            uint256 maxIntrinsicUsd = strikePricesWithPrecision[1] - strikePricesWithPrecision[0];
            intrinsicUsd = intrinsicUsd > maxIntrinsicUsd ? maxIntrinsicUsd : intrinsicUsd;
        }
        
        else if (isNakedPut && strikePricesWithPrecision[0] > _settlePrice) { // Put
            isItm = true;
            unchecked {
                intrinsicUsd = strikePricesWithPrecision[0] - _settlePrice;
            }
        }
        
        else if (isPutSpread && strikePricesWithPrecision[1] > _settlePrice) {
            isItm = true;
            unchecked {
                intrinsicUsd = strikePricesWithPrecision[1] - _settlePrice;
            }
            uint256 maxIntrinsicUsd = strikePricesWithPrecision[1] - strikePricesWithPrecision[0];
            intrinsicUsd = intrinsicUsd > maxIntrinsicUsd ? maxIntrinsicUsd : intrinsicUsd;
        }
    }
    
    //////////////////////////////////////////////
    //  Fee Management                          //
    //////////////////////////////////////////////

    function setHasDynamicFees(bool _hasDynamicFees) external onlyAdmin {
        hasDynamicFees = _hasDynamicFees;
        emit SetHasDynamicFees(_hasDynamicFees);
    }

    function setTradeFeeCalculationLimitRate(uint256 _tradeFeeCalculationLimitRate) external onlyAdmin {
        if (_tradeFeeCalculationLimitRate > BASIS_POINTS_DIVISOR) { revert LimitExceeded(); }
        tradeFeeCalculationLimitRate = _tradeFeeCalculationLimitRate;
        emit SetTradeFeeCalculationLimitRate(_tradeFeeCalculationLimitRate);
    }

    function setSettleFeeCalculationLimitRate(uint256 _settleFeeCalculationLimitRate) external onlyAdmin {
        if (_settleFeeCalculationLimitRate > BASIS_POINTS_DIVISOR) { revert LimitExceeded(); }
        settleFeeCalculationLimitRate = _settleFeeCalculationLimitRate;
        emit SetSettleFeeCalculationLimitRate(_settleFeeCalculationLimitRate);
    }

    function setReferral(address _referral) external onlyAdmin {
        if (_referral == address(0)) { revert ZeroAddress(); }
        referral = _referral;
        emit SetReferral(_referral);
    }

    function setFees(
        uint256 _openBuyNakedPositionFee, // 1.
        uint256 _openSellNakedPositionFee, // 2.
        uint256 _openComboPositionFee, // 3.
        uint256 _closeNakedPositionFee, // 4.
        uint256 _closeComboPositionFee, // 5.
        uint256 _settlePositionFee, // 6.
        uint256 _taxFee, // 7.
        uint256 _stableTaxFee, // 8.
        uint256 _mintBurnFee, // 9.
        uint256 _swapFee, // 10.
        uint256 _stableSwapFee // 11.
    ) external onlyAdmin {
        if (
            _openBuyNakedPositionFee > MAX_FEE ||
            _openSellNakedPositionFee > MAX_FEE ||
            _openComboPositionFee > MAX_FEE ||
            _closeNakedPositionFee > MAX_FEE ||
            _closeComboPositionFee > MAX_FEE ||
            _settlePositionFee > MAX_FEE ||
            _taxFee > MAX_FEE ||
            _stableTaxFee > MAX_FEE ||
            _mintBurnFee > MAX_FEE ||
            _swapFee > MAX_FEE ||
            _stableSwapFee > MAX_FEE
        ) { revert LimitExceeded(); }

        // Emit before setting fees, so that the old value is visible in the event
        emit SetFee("OPEN_BUY_NAKED_POSITION_FEE", OPEN_BUY_NAKED_POSITION_FEE, _openBuyNakedPositionFee);
        emit SetFee("OPEN_SELL_NAKED_POSITION_FEE", OPEN_SELL_NAKED_POSITION_FEE, _openSellNakedPositionFee);
        emit SetFee("OPEN_COMBO_POSITION_FEE", OPEN_COMBO_POSITION_FEE, _openComboPositionFee);
        emit SetFee("CLOSE_NAKED_POSITION_FEE", CLOSE_NAKED_POSITION_FEE, _closeNakedPositionFee);
        emit SetFee("CLOSE_COMBO_POSITION_FEE", CLOSE_COMBO_POSITION_FEE, _closeComboPositionFee);
        emit SetFee("SETTLE_POSITION_FEE", SETTLE_POSITION_FEE, _settlePositionFee);
        emit SetFee("TAX_FEE", TAX_FEE, _taxFee);
        emit SetFee("STABLE_TAX_FEE", STABLE_TAX_FEE, _stableTaxFee);
        emit SetFee("MINT_BURN_FEE", MINT_BURN_FEE, _mintBurnFee);
        emit SetFee("SWAP_FEE", SWAP_FEE, _swapFee);
        emit SetFee("STABLE_SWAP_FEE", STABLE_SWAP_FEE, _stableSwapFee); 

        OPEN_BUY_NAKED_POSITION_FEE = _openBuyNakedPositionFee;
        OPEN_SELL_NAKED_POSITION_FEE = _openSellNakedPositionFee;
        OPEN_COMBO_POSITION_FEE = _openComboPositionFee;
        CLOSE_NAKED_POSITION_FEE = _closeNakedPositionFee;
        CLOSE_COMBO_POSITION_FEE = _closeComboPositionFee;
        SETTLE_POSITION_FEE = _settlePositionFee;
        TAX_FEE = _taxFee;
        STABLE_TAX_FEE = _stableTaxFee;
        MINT_BURN_FEE = _mintBurnFee;
        SWAP_FEE = _swapFee;
        STABLE_SWAP_FEE = _stableSwapFee;
    }

    /*
     * @dev Get fee info for position
     * @return afterFeePaidAmount The amount after fee paid
     * @return size The size after fee paid
     * @return feeUsd The fee in USD
     * @return feeAmount The fee in token
     * @return parent The parent address
     * @return feeRebateRate The fee rebate rate
     */
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
        uint _requestIndex
    ) public override view returns (uint256, uint256, uint256, uint256, address, uint256, bool) {
        (uint256 feeBps, uint256 discountRate, address parent, uint256 feeRebateRate) = getPositionFeeBasisPoints(_account, _strategy, _isOpen, _isSettle);

        uint256 feeUsd = 0;
        uint256 feeAmount = 0;

        uint256 decimals = IVault(vault).tokenDecimals(_underlyingAsset);

        if (_isSettle) {
            feeUsd = (_price * _size / (10 ** decimals)) * feeBps / BASIS_POINTS_DIVISOR * (BASIS_POINTS_DIVISOR - discountRate) / BASIS_POINTS_DIVISOR;
            feeAmount = IVault(vault).usdToToken(_token, feeUsd, true);
            uint256 maxFeeAmount = _amount * settleFeeCalculationLimitRate / BASIS_POINTS_DIVISOR;
            
            feeAmount = feeAmount > maxFeeAmount ? maxFeeAmount : feeAmount;
            feeUsd = IVault(vault).tokenToUsdMin(_token, feeAmount);
        } else {
            uint256 underlyingAssetPrice = IVault(vault).getSpotPrice(_underlyingAsset, true);

            feeUsd = (underlyingAssetPrice * _size / (10 ** decimals)) * feeBps / BASIS_POINTS_DIVISOR * (BASIS_POINTS_DIVISOR - discountRate) / BASIS_POINTS_DIVISOR;
            uint256 maxFeeUsd = (_price * _size) / (10 ** decimals) * tradeFeeCalculationLimitRate / BASIS_POINTS_DIVISOR; // Total Execution Price의 50%

            feeUsd = feeUsd > maxFeeUsd ? maxFeeUsd : feeUsd;
            feeAmount = IVault(vault).usdToToken(_token, feeUsd, true);
        }

        if (_amount < feeAmount) { revert InsufficientAmountOrSize(); }

        uint256 afterFeePaidAmount = _amount - feeAmount;

        if (_isOpen && !_isSettle) {
            _size = _size * afterFeePaidAmount / _amount;
            if (_size == 0) { revert InsufficientAmountOrSize(); }
        }

        address rebateReceiver = parent;
        bool isCopyTrade = false;

        if (_isOpen) {
            address _leadTrader = IPositionManager(positionManager).leadTrader(_requestIndex);
            if (_leadTrader != address(0)) {
                rebateReceiver = _leadTrader;
                feeRebateRate = IPositionManager(positionManager).copyTradeFeeRebateRate();
                isCopyTrade = true;
            }
        }

        return (afterFeePaidAmount, _size, feeUsd, feeAmount, rebateReceiver, feeRebateRate, isCopyTrade);
    }

    /*
     * @dev Get fee basis points for position
     * @return feeBps The fee basis points
     * @return discountRate The discount rate
     * @return parent The parent address
     * @return feeRebateRate The fee rebate rate
     */
    function getPositionFeeBasisPoints(address _account, Utils.Strategy _strategy, bool _isOpen, bool _isSettle) public override view returns (uint256, uint256, address, uint256) {
        if (_account == address(0)) { revert ZeroAddress(); }
        
        if (_isSettle) return (SETTLE_POSITION_FEE, 0, address(0), 0);

        uint256 feeBps = 0;

        if (_isOpen) {
            if (Utils.isNaked(_strategy)) {
                feeBps = Utils.isBuy(_strategy) ? OPEN_BUY_NAKED_POSITION_FEE : OPEN_SELL_NAKED_POSITION_FEE;
            } else {
                feeBps = OPEN_COMBO_POSITION_FEE;
            }
        } else {
            if (Utils.isNaked(_strategy)) {
                feeBps = CLOSE_NAKED_POSITION_FEE;
            } else {
                feeBps = CLOSE_COMBO_POSITION_FEE;
            }
        }
        
        if (referral == address(0)) { return (feeBps, 0, address(0), 0); }
        
        (uint256 discountRate, address parent, uint256 feeRebateRate) = IReferral(referral).getRateInfo(_account);
        return (feeBps, discountRate, parent, feeRebateRate);
    }

    function getBuyUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) public override view returns (uint256) {
        return getFeeBasisPoints(_token, _usdgAmount, MINT_BURN_FEE, TAX_FEE, true);
    }

    function getSellUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) public override view returns (uint256) {
        return getFeeBasisPoints(_token, _usdgAmount, MINT_BURN_FEE, TAX_FEE, false);
    }

    // if tokenIn and tokenOut are both stableTokens, use stableSwapFeeBasisPoints (0.04%) for baseBps and stableTaxBasisPoints (0.2%) for taxBps
    // if tokenIn or tokenOut is not stableToken, use swapFeeBasisPoints (0.3%) for baseBps and taxBasisPoints (0.5%) for taxBps
    // get feeBasisPoints for tokenIn and tokenOut, use the higher of the two
    function getSwapFeeBasisPoints(address _tokenIn, address _tokenOut, uint256 _usdgAmount) public override view returns (uint256) {
        bool isStableSwap = IVault(vault).isStableToken(_tokenIn) && IVault(vault).isStableToken(_tokenOut);
        uint256 baseBps = isStableSwap ? STABLE_SWAP_FEE : SWAP_FEE;
        uint256 taxBps = isStableSwap ? STABLE_TAX_FEE : TAX_FEE;
        uint256 feesBasisPoints0 = getFeeBasisPoints(_tokenIn, _usdgAmount, baseBps, taxBps, true);
        uint256 feesBasisPoints1 = getFeeBasisPoints(_tokenOut, _usdgAmount, baseBps, taxBps, false);
        // use the higher of the two fee basis points
        return feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) public override view returns (uint256) {
        if (!hasDynamicFees) { return _feeBasisPoints; }

        uint256 initialAmount = IVault(vault).usdgAmounts(_token); // get usdgAmount of _token => initialAmount
        uint256 nextAmount = initialAmount + _usdgDelta;

        // if _usdgDelta is negative, nextAmount should be adjusted (as nextAmount cannot be negative)
        if (!_increment) {
            if (_usdgDelta > initialAmount) {
                nextAmount = 0;
            } else {
                unchecked { nextAmount = initialAmount - _usdgDelta; }
            }
        }

        // get targetAmount of _token
        // targetAmount is the amount of USDG that should be in the vault to maintain the weight of _token
        uint256 targetAmount = IVault(vault).getTargetUsdgAmount(_token);
        if (targetAmount == 0) { return _feeBasisPoints; }
        
        // calculate initialDiff between initialAmount and targetAmount
        // calculate nextDiff between nextAmount and targetAmount
        uint256 initialDiff = initialAmount > targetAmount ? initialAmount - targetAmount : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount ? nextAmount - targetAmount : targetAmount - nextAmount;

        // if nextDiff is smaller than initialDiff, then the action improves the relative asset balance
        // in this case, we want to reduce the feeBasisPoints by the rebateBps
        if (nextDiff < initialDiff) {
            uint256 rebateBps = _taxBasisPoints * initialDiff / targetAmount;
            if (rebateBps > _feeBasisPoints) {
                return 0;
            } else {
                unchecked { return _feeBasisPoints - rebateBps; }
            }
        }

        // if nextDiff is larger than initialDiff, then the action worsens the relative asset balance
        // in this case, we want to increase the feeBasisPoints by the taxBps
        uint256 averageDiff = (initialDiff + nextDiff) / 2;
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = _taxBasisPoints * averageDiff / targetAmount;
        return _feeBasisPoints + taxBps;
    }

    
    //////////////////////////////////////////////
    //  MP and RP Management                    //
    //////////////////////////////////////////////

    function setReleaseDuration(address _token, uint256 _releaseDuration, PriceType _priceType) public override onlyKeeper {
        IVault(vault).updatePendingAmount(_token);

        uint256 leftover = (_priceType == IVaultUtils.PriceType.MP)
            ? IVault(vault).pendingMpAmounts(_token)
            : IVault(vault).pendingRpAmounts(_token);

        if (_releaseDuration == 0) {
            releaseRate[_priceType][_token] = leftover;
        } else {
            releaseRate[_priceType][_token] = leftover / _releaseDuration;
        }

        lastUpdateTime[_priceType][_token] = block.timestamp;
        
        periodFinish[_priceType][_token] = block.timestamp + _releaseDuration;

        releaseDuration[_priceType][_token] = _releaseDuration;

        emit SetReleaseDuration(_token, _releaseDuration, _priceType);
    }

    function notifyPendingAmount(PriceType _priceType, address _token, uint256 _pendingUsd, uint256 _pendingAmount) external override onlyVault  {
        IVault(vault).updatePendingAmount(_token);

        uint256 leftover = (_priceType == IVaultUtils.PriceType.MP)
            ? IVault(vault).pendingMpAmounts(_token)
            : IVault(vault).pendingRpAmounts(_token);

        uint256 targetReleaseDuration = releaseDuration[_priceType][_token];

        if (targetReleaseDuration == 0) {
            releaseRate[_priceType][_token] = _pendingAmount + leftover;
        } else {
            releaseRate[_priceType][_token] = (_pendingAmount + leftover) / targetReleaseDuration;
        }

        lastUpdateTime[_priceType][_token] = block.timestamp;

        periodFinish[_priceType][_token] = block.timestamp + targetReleaseDuration;

        emit NotifyPendingAmount(_priceType, _token, _pendingUsd, _pendingAmount);
    }

    function getReleaseAmountAll(address _token) external override onlyVault returns (uint256, uint256) {
        uint256 mpReleaseAmount = _getReleaseAmount(PriceType.MP, _token);
        uint256 rpReleaseAmount = _getReleaseAmount(PriceType.RP, _token);

        return (mpReleaseAmount, rpReleaseAmount);
    }

    function _getReleaseAmount(PriceType _priceType, address _token) private returns (uint256 releaseAmount) {
        uint256 targetReleaseRate = releaseRate[_priceType][_token];
        
        if (releaseDuration[_priceType][_token] == 0) {
            releaseAmount = targetReleaseRate;
            releaseRate[_priceType][_token] = 0;
        } else {
            uint256 lastTimeRelease = _lastTimeReleaseApplicable(_token, _priceType);
            uint256 elapsed = lastTimeRelease - lastUpdateTime[_priceType][_token];
            
            releaseAmount = elapsed * targetReleaseRate;
            
            lastUpdateTime[_priceType][_token] = lastTimeRelease;
        }
    }

    function _lastTimeReleaseApplicable(address _token, PriceType _priceType) private view returns (uint256) {  
        uint256 targetPeriodFinish = periodFinish[_priceType][_token];  
        return block.timestamp < targetPeriodFinish
            ? block.timestamp 
            : targetPeriodFinish;
    }


    //////////////////////////////////////////////
    //  Management of Vault's Positions         //
    //////////////////////////////////////////////

    function getSelfOriginExpiries() external override view returns (uint256[] memory) {
        return selfOriginExpiries;
    }

    function getSelfOriginExpiriesLength() external override view returns (uint256) {
        return selfOriginExpiries.length;
    }

    function getOptionTokensAtSelfOriginExpiry(uint256 _expiry) external override view returns (OptionToken[] memory) {
        return optionTokensAtSelfExpiry[_expiry];
    }

    function getOptionTokensLengthAtSelfExpiry(uint256 _expiry) external view override returns (uint256) {
        return optionTokensAtSelfExpiry[_expiry].length;
    }

    function getSelfOriginExpiriesToSettle() external override view returns (uint256[] memory) {
        return selfOriginExpiriesToSettle;
    }

    function isInSettlementProgress() external view override returns (bool) {
        if (selfOriginExpiriesToSettle.length > 0) {
            return true;
        }

        uint256 currentTime = block.timestamp;

        for (uint256 i = 0; i < selfOriginExpiries.length;) {
            if (selfOriginExpiries[i] <= currentTime) {
                return true;
            }
            unchecked { i++; }
        }

        return false;   
    }

    function updateVaultPositionAfterTrade(uint256 _expiry, uint256 _optionTokenId, uint256 _size, bool _isAdd) external override onlyController {
        // If an option token is being added, add the respective expiry
        if (_isAdd) {
            _addExpiry(_expiry, false);
        }
        
        // Retrieve option tokens held at the given expiry
        OptionToken[] storage tokens = optionTokensAtSelfExpiry[_expiry];
    
        // If there is an option token with the same ID
        for (uint256 i = 0; i < tokens.length;) {
            OptionToken storage token = tokens[i];
            if (token.optionTokenId == _optionTokenId) {
                if (_isAdd) {
                    token.size += _size;
                } else {
                    if (token.size < _size) { revert InsufficientAmountOrSize(); }
                    unchecked {
                        token.size -= _size;
                    }
                }
                return;
            }
            unchecked { i++; }
        }

        // If there is no option token with the same ID
        if (_isAdd) {
            OptionToken memory newOptionToken;
            newOptionToken.optionTokenId = _optionTokenId;
            newOptionToken.size = _size;
            optionTokensAtSelfExpiry[_expiry].push(newOptionToken);
            return;
        }

        revert NotFound();
    }

    // utils for manual settlement
    function addExpiryToArray(uint256 _expiry, bool _isSettle) external override onlyAdmin {
        _addExpiry(_expiry, _isSettle);
    }

    function removeExpiryFromArray(uint256 _expiry, bool _isSettle) external override onlyAdmin {
        _removeExpiry(_expiry, _isSettle);
    }

    function setIsPositionSettled (uint256 _expiry, bool _isPositionSettled) external override onlyAdmin {
        isPositionAtSelfExpirySettled[_expiry] = _isPositionSettled;
    }

    function setOptionTokensStart(uint256 _expiry, uint256 _optionTokensStart) external override onlyAdmin {
        optionTokensAtSelfExpiryStart[_expiry] = _optionTokensStart;
    }

    // utils for auto settlement
    function prepareExpiriesToSettle() external override {
        _prepareExpiriesToSettle();
    }

    function settleSelfOriginPositions(uint256 _expiry, uint256 _endLength) external onlyKeeper returns (bool) {
        if (isPositionAtSelfExpirySettled[_expiry]) { revert AlreadySettled(); }

        uint256 index = optionTokensAtSelfExpiryStart[_expiry]; // 0, 1, 2
        uint256 length = optionTokensAtSelfExpiry[_expiry].length; // 3

        if (index == length) {
            _removeExpiry(_expiry, true);
            isPositionAtSelfExpirySettled[_expiry] = true;
            emit VaultPositionSettled(address(vault), _expiry);
            return true;
        }
        
        if (_endLength > length) {
            _endLength = length;
        }

        while(index < _endLength) {
            IVaultUtils.OptionToken memory token = optionTokensAtSelfExpiry[_expiry][index];
            
            bool shouldContinue = true;

            if (token.size > 0) {
                address quotetoken = _getQuoteTokenForSettlement(token.optionTokenId);
                address[] memory path = new address[](1);
                path[0] = quotetoken;

                uint16 underlyingAssetIndex = Utils.getUnderlyingAssetIndexByOptionTokenId(token.optionTokenId);
                
                try IVault(vault).settleVaultPosition(
                    path,
                    underlyingAssetIndex,
                    token.optionTokenId
                ) returns (uint256 _amountOut)  {
                    if (_amountOut > 0) {
                        IVault(vault).directPoolDeposit(quotetoken);
                    }
                } catch {
                    shouldContinue = false;
                }
            }

            if (shouldContinue) {
                delete optionTokensAtSelfExpiry[_expiry][index];
                index++;
            } else {
                break;
            }
        }

        optionTokensAtSelfExpiryStart[_expiry] = index;

        if (index == length) {
            _removeExpiry(_expiry, true);
            isPositionAtSelfExpirySettled[_expiry] = true;
            emit VaultPositionSettled(address(vault), _expiry);
        }

        return true;
    }


    //////////////////////////////////////////////
    //  Internal Functions                      //
    //////////////////////////////////////////////

    function _prepareExpiriesToSettle() internal {
        uint256[] memory targetExpiries = selfOriginExpiries;

        uint256 currentTime = block.timestamp;

        uint256 i = 0;
        while (i < targetExpiries.length) {
            if (targetExpiries[i] <= currentTime) {
                _migrateExpiryToSettle(targetExpiries[i]);
            }
            i++;
        }
    }

    function _migrateExpiryToSettle(uint256 _expiry) internal {
        _removeExpiry(_expiry, false);
        _addExpiry(_expiry, true);
    }

    function _getQuoteTokenForSettlement(uint256 _optionTokenId) internal view returns (address) {
        (uint16 underlyingAssetIndex,, Utils.Strategy strategy,,,,,) = Utils.parseOptionTokenId(_optionTokenId);
        
        address mainStableAsset = IVault(vault).getMainStableAsset();
        address underlyingAsset = IVault(vault).getUnderlyingAssetByIndex(underlyingAssetIndex);

        bool isNakedCall = Utils.isNaked(strategy) && Utils.isCall(strategy);

        if (isNakedCall) {
            return underlyingAsset;
        } else {
            return mainStableAsset;
        }
    }

    function _addExpiry(uint256 _expiry, bool _isSettle) internal {
        if (!_isSettle) {
            if (isSelfExpiryAdded[_expiry]) { return; }
            selfOriginExpiries.push(_expiry);
            selfExpiryIndex[_expiry] = selfOriginExpiries.length - 1;
            isSelfExpiryAdded[_expiry] = true;
        } else {
            selfOriginExpiriesToSettle.push(_expiry);
            selfExpiryToSettleIndex[_expiry] = selfOriginExpiriesToSettle.length - 1;
        }
    }

    function _removeExpiry(uint256 _expiry, bool _isSettle) internal {
        uint256[] storage targetArray = !_isSettle
            ? selfOriginExpiries
            : selfOriginExpiriesToSettle;

        mapping(uint256 => uint256) storage targetIndexMap = !_isSettle
            ? selfExpiryIndex
            : selfExpiryToSettleIndex;

        uint256 index = targetIndexMap[_expiry];
        if (index >= targetArray.length || targetArray[index] != _expiry) { revert NotFound(); }

        uint256 lastIndex = targetArray.length - 1;

        if (index != lastIndex) {
            // Move the last element to the deleted spot to maintain compact array
            uint256 lastElement = targetArray[lastIndex];
            targetArray[index] = lastElement;
            targetIndexMap[lastElement] = index;
        }
        
        // Remove the last element
        targetArray.pop();
        delete targetIndexMap[_expiry];
    }
}
