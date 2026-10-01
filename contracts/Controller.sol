// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IOptionsMarket.sol";
import "./interfaces/IController.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./tokens/interfaces/IOptionsToken.sol";
import "./tokens/interfaces/IWNAT.sol";
import "./tokens/interfaces/IERC20.sol";
import "./tokens/libraries/SafeERC20.sol";
import "./tokens/erc1155/interfaces/IERC1155Base.sol";
import "./oracles/interfaces/IVaultPriceFeed.sol";
import "./libraries/Address.sol";
import "./AuthorityUtil.sol";
import "./proxy/OwnableUpgradeable.sol";

contract Controller is IController, OwnableUpgradeable, AuthorityUtil {
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant PRICE_PRECISION = 10 ** 30;

    address public optionsMarket;
    address public vaultPriceFeed;
    
    // @desc The address of the wrapped native token (WNAT)
    // @info
    // - For Arbitrum, WNAT is the wrapped ETH token
    // - For Berachain, WNAT is the wrapped BERA token
    address public wnat;

    uint256 public override maxGasPrice;

    address[3] public vaults;

    mapping (address => address) public vaultToVaultUtil;
    
    mapping (address => bool) public plugins; // plugins: PositionManager, FeeDistributor

    mapping (uint16 => mapping (bool => uint256)) public accumulatedNotionalVolume; // underlyingAssetIndex => isCall => notionalVolume
    mapping (uint16 => mapping (bool => uint256)) public accumulatedExecutionPrice; // underlyingAssetIndex => isCall => totalExecutionPrice

    // @desc Check whether OLP supports native token or not
    // @info
    // - For Arbitrum, OLP supports native token
    // - For Berachain, OLP does not support native token
    bool public override isNATSupported;

    uint256 public allowedStrategiesMask; // bitmask of allowed strategies

    event SetMaxGasPrice(uint256 indexed maxGasPrice);
    event SetIsNATSupported(bool indexed isNATSupported);
    event SetOptionsMarket(address indexed optionsMarket);
    event SetVaultPriceFeed(address indexed vaultPriceFeed);
    event SetVault(uint8 indexed vaultIndex, address indexed vault, address indexed vaultUtils);
    event UpdatePlugin(address indexed plugin, bool isPlugin);
    event Swap(address account, address vault, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    event OpenBuyPosition(
        address indexed account,
        uint256 requestIndex,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,

        address quoteToken,
        uint256 amountPaid,
        uint256 executionPrice,
        uint256 spotPrice
    );

    event OpenSellPosition(
        address indexed account,
        uint256 requestIndex,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,

        address quoteToken,
        uint256 amountReceived,
        address collateralToken,
        uint256 collateralAmount,
        uint256 executionPrice,
        uint256 spotPrice
    );

    event CloseBuyPosition(
        address indexed account,
        uint256 requestIndex,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,

        address quoteToken,
        uint256 amountReceived,
        uint256 executionPrice,
        uint256 spotPrice
    );

    event CloseSellPosition(
        address indexed account,
        uint256 requestIndex,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,

        address quoteToken,
        uint256 amountPaid,
        address collateralToken,
        uint256 collateralAmount,
        uint256 executionPrice,
        uint256 spotPrice
    );

    event SettleBuyPosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,

        address quoteToken,
        uint256 amountReceived,
        uint256 settlePrice
    );

    event SettleSellPosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,
        
        address quoteToken,
        uint256 amountPaid,
        address collateralToken,
        uint256 collateralAmount,
        uint256 settlePrice
    );

    event ClearPosition(
        address indexed vault,
        address indexed optionsToken,
        uint256 indexed optionTokenId,
        uint256 oppositeOptionTokenId,
        uint256 sizeToClear
    );

    event IncreaseAccumulatedNotionalVolume(uint16 indexed underlyingAssetIndex, bool indexed isCall, uint256 notionalVolume);
    event IncreaseAccumulatedExecutionPrice(uint16 indexed underlyingAssetIndex, bool indexed isCall, uint256 totalExecutionPrice);
    event SetAllowedStrategiesMask(uint256 indexed mask);

    error ExpiredOptionId();
    error GasPriceExceeded();
    error InvalidPlugin();
    error InvalidPath();
    error InvalidSender();
    error InvalidTime();
    error InvalidVault();
    error InsufficientOutput();
    error NATNotSupported();
    error NotSupportedStrategy();
    error StrategyNotAllowed();
    error TradingNotAllowed();
    error QuoteTokenMismatch();
    error ZeroAddress();

    function initialize(
        address[3] memory _vaults,
        address[3] memory _vaultUtils,
        address _optionsMarket,
        address _vaultPriceFeed,
        address _wnat,
        IOptionsAuthority _authority,
        bool _isNATSupported
    ) public initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        isNATSupported = _isNATSupported;

        if (_optionsMarket == address(0) || _vaultPriceFeed == address(0) || _wnat == address(0)) { revert ZeroAddress(); }
        
        optionsMarket = _optionsMarket;
        vaultPriceFeed = _vaultPriceFeed;
        wnat = _wnat;
        
        for (uint256 i = 0; i < vaults.length;) {
            if (_vaults[i] == address(0) || _vaultUtils[i] == address(0)) { revert ZeroAddress(); }
            vaultToVaultUtil[_vaults[i]] = _vaultUtils[i];
            unchecked { i++; }
        }
        
        vaults = _vaults;
    }

    receive() external payable {
        if (msg.sender != wnat) { revert InvalidSender(); }
    }

    function setMaxGasPrice(uint256 _maxGasPrice) external onlyAdmin {
        maxGasPrice = _maxGasPrice;
        emit SetMaxGasPrice(_maxGasPrice);
    }

    function setIsNATSupported(bool _isNATSupported) external onlyAdmin {
        isNATSupported = _isNATSupported;
        emit SetIsNATSupported(_isNATSupported);
    }

    function setOptionsMarket (address _optionsMarket) external onlyAdmin {
        optionsMarket = _optionsMarket;
        emit SetOptionsMarket(_optionsMarket);
    }

    function setVaultPriceFeed(address _vaultPriceFeed) external onlyAdmin {
        if (_vaultPriceFeed == address(0)) { revert ZeroAddress(); }
        vaultPriceFeed = _vaultPriceFeed;
        emit SetVaultPriceFeed(_vaultPriceFeed);
    }

    function setVault(uint8 _vaultIndex, address _vault) external override onlyAdmin {
        if (_vault == address(0)) { revert ZeroAddress(); }
        if (_vaultIndex >= vaults.length) { revert InvalidVault(); }

        vaults[_vaultIndex] = _vault;

        address vaultUtils = address(IVault(_vault).vaultUtils());
        if (vaultUtils == address(0)) { revert ZeroAddress(); }
        vaultToVaultUtil[_vault] = vaultUtils;

        emit SetVault(_vaultIndex, _vault, vaultUtils);
    }

    /// @notice Set allowed strategies for trading
    /// @dev Allows or disallows multiple strategies at once using a bitmask
    /// @param _strategies Array of strategies to allow/disallow
    ///     0 = NotSupported (cannot be set)
    ///     1 = BuyCall
    ///     2 = SellCall
    ///     3 = BuyPut
    ///     4 = SellPut
    ///     5 = BuyCallSpread
    ///     6 = SellCallSpread
    ///     7 = BuyPutSpread
    ///     8 = SellPutSpread
    /// @param _isAllowed true to allow strategies, false to disallow
    /// 
    /// Usage examples:
    ///     // Allow BuyCall and BuyPut strategies
    ///     setAllowedStrategies([Utils.Strategy.BuyCall, Utils.Strategy.BuyPut], true);
    ///     
    ///     // Disallow SellCall strategy
    ///     setAllowedStrategies([Utils.Strategy.SellCall], false);
    function setAllowedStrategies(Utils.Strategy[] calldata _strategies, bool _isAllowed) external onlyAdmin {
        uint256 mask = allowedStrategiesMask;

        for (uint256 i = 0; i < _strategies.length; ) {
            Utils.Strategy s = _strategies[i];
            if (s == Utils.Strategy.NotSupported) { revert NotSupportedStrategy(); }
            uint256 b = _bit(uint8(s));

            if (_isAllowed) {
                mask |= b;
            } else {
                mask &= ~b;
            }

            unchecked {
                i++;
            }
        }

        allowedStrategiesMask = mask;
        emit SetAllowedStrategiesMask(mask);
    }

    function getVaults() external view override returns (address[3] memory) {
        return vaults;
    }

    function getVaultAddressByIndex(uint8 _vaultIndex) public view override returns (address) {
        if (_vaultIndex >= vaults.length) { revert InvalidVault(); }
        return vaults[_vaultIndex];
    }

    function getVaultAddressByOptionTokenId(uint256 _optionTokenId) public view override returns (address) {
        uint8 vaultIndex = Utils.getVaultIndexByOptionTokenId(_optionTokenId);
        return vaults[vaultIndex];
    }

    function getVaultIndexByTimeGap(uint40 _standardTime, uint40 _expiry) public view override returns (uint8) {
        if (_expiry <= _standardTime) { revert InvalidTime(); }

        uint40 diff = _expiry - _standardTime;

        uint40 sVaultThresholdDays = IVault(vaults[0]).thresholdDays();
        uint40 mVaultThresholdDays = IVault(vaults[1]).thresholdDays();
        uint40 lVaultThresholdDays = IVault(vaults[2]).thresholdDays();

        if (diff > lVaultThresholdDays) { revert InvalidTime(); }

        if (diff <= sVaultThresholdDays) return 0;
        if (diff <= mVaultThresholdDays) return 1;
        return 2;
    }

    function isVault(address _account) public override view returns (bool) {
        return _account == vaults[0] || _account == vaults[1] || _account == vaults[2];
    }

    function getSpotPriceByUnderlyingAssetIndex(uint16 _underlyingAssetIndex) public view override returns (uint256) {
        address underlyingAsset = IOptionsMarket(optionsMarket).indexToUnderlyingAsset(_underlyingAssetIndex);
        return IVaultPriceFeed(vaultPriceFeed).getSpotPrice(underlyingAsset, true);
    }

    function getNotionalVolume(uint16[] memory _underlyingAssetIndexes) external override view returns (uint256 acc) {
        for (uint256 i = 0; i < _underlyingAssetIndexes.length; i++) {
            acc += accumulatedNotionalVolume[_underlyingAssetIndexes[i]][true];
            acc += accumulatedNotionalVolume[_underlyingAssetIndexes[i]][false];
        }
    }

    function getNotionalVolumeByOptionType(uint16[] memory _underlyingAssetIndexes, bool _isCall) external override view returns (uint256 acc) {
        for (uint256 i = 0; i < _underlyingAssetIndexes.length; i++) {
            acc += accumulatedNotionalVolume[_underlyingAssetIndexes[i]][_isCall];
        }
    }

    function getTotalExecutionPrice(uint16[] memory _underlyingAssetIndexes) external override view returns (uint256 acc) {
        for (uint256 i = 0; i < _underlyingAssetIndexes.length; i++) {
            acc += accumulatedExecutionPrice[_underlyingAssetIndexes[i]][true];
            acc += accumulatedExecutionPrice[_underlyingAssetIndexes[i]][false];
        }
    }

    function getTotalExecutionPriceByOptionType(uint16[] memory _underlyingAssetIndexes, bool _isCall) external override view returns (uint256 acc) {
        for (uint256 i = 0; i < _underlyingAssetIndexes.length; i++) {
            acc += accumulatedExecutionPrice[_underlyingAssetIndexes[i]][_isCall];
        }
    }

    function validateNATSupport() public view override {
        _validateNATSupport();
    }
    
    function addPlugin(address _plugin) external override onlyAdmin {
        plugins[_plugin] = true;
        emit UpdatePlugin(_plugin, true);
    }

    function removePlugin(address _plugin) external onlyAdmin {
        plugins[_plugin] = false;
        emit UpdatePlugin(_plugin, false);
    }

    function pluginERC20Transfer(address _token, address _account, address _receiver, uint256 _amount) external override {
        _validatePlugin();
        IERC20(_token).safeTransferFrom(_account, _receiver, _amount);
    }

    function pluginERC1155Transfer(address _optionsToken, address _account, address _receiver, uint256 _optionTokenId, uint256 _amount) external override {
        _validatePlugin();
        IERC1155Base(_optionsToken).safeTransferFrom(_account, _receiver, _optionTokenId, _amount, "");
    }

    function pluginOpenPosition(
        address _account,
        uint256 _requestIndex,
        address _quoteToken,
        uint256 _optionTokenId,
        uint256 _minSize,
        address _receiver,
        address _vault
    ) external override returns (uint256, uint256, uint256) {
        _validatePlugin();
        _validateGasPrice();

        (
            uint16 underlyingAssetIndex,
            uint40 expiry,
            Utils.Strategy strategy,
            uint8 length,
            ,
            uint48[4] memory strikePrices,
            ,
        ) = Utils.parseOptionTokenId(_optionTokenId);
        _validateStrategy(strategy);
        _validateQuoteToken(strategy, _quoteToken, underlyingAssetIndex, false);

        (
            uint256 sizeOut,
            uint256 executionPrice,
            address utilizedToken,
            uint256 utilizedAmount,
            address tokenOut,
            uint256 amountOut,
            uint256 afterFeePaidAmount
        ) = IVault(_vault).openPosition(
            _account,
            _requestIndex,
            _optionTokenId,
            underlyingAssetIndex,
            strategy,
            strikePrices,
            _quoteToken,
            _receiver
        );
        if (sizeOut < _minSize) { revert InsufficientOutput(); }

        address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(underlyingAssetIndex);
        uint256 oppositeOptionTokenId = Utils.getOppositeOptionTokenId(_optionTokenId);
        
        if (sizeOut > 0) {    
            IOptionsToken(optionsToken).mint(_receiver, _optionTokenId, sizeOut);
            IOptionsToken(optionsToken).mint(_vault, oppositeOptionTokenId, sizeOut);
            IVaultUtils(vaultToVaultUtil[_vault]).updateVaultPositionAfterTrade(expiry, oppositeOptionTokenId, sizeOut, true);
        }

        // increase notional volume
        bool isCall = Utils.isCall(strategy);

        uint256 spotPrice = getSpotPriceByUnderlyingAssetIndex(underlyingAssetIndex);

        (, uint8 decimals) = IOptionsMarket(optionsMarket).getUnderlyingAssetByIndex(underlyingAssetIndex);

        for (uint256 i = 0; i < length; i++) {
            accumulatedNotionalVolume[underlyingAssetIndex][isCall] += sizeOut * spotPrice / (10 ** decimals);
            emit IncreaseAccumulatedNotionalVolume(underlyingAssetIndex, isCall, sizeOut * spotPrice / (10 ** decimals));
        }
        
        accumulatedExecutionPrice[underlyingAssetIndex][isCall] += sizeOut * executionPrice / (10 ** decimals);
        emit IncreaseAccumulatedExecutionPrice(underlyingAssetIndex, isCall, sizeOut * executionPrice / (10 ** decimals));

        if (Utils.isBuy(strategy)) {
            emit OpenBuyPosition(
                _account,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                sizeOut,

                _quoteToken,
                afterFeePaidAmount,
                executionPrice,
                spotPrice
            );

            emit OpenSellPosition(
                _vault,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                oppositeOptionTokenId,
                sizeOut,

                _quoteToken,
                afterFeePaidAmount,
                utilizedToken, // collateral token by olp
                utilizedAmount, // collateral amount by olp
                executionPrice,
                spotPrice
            );
        } else {
            emit OpenSellPosition(
                _account,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                sizeOut,

                tokenOut,
                amountOut,
                _quoteToken, // collateral token by trader
                afterFeePaidAmount, // collateral amount by trader
                executionPrice,
                spotPrice
            );

            emit OpenBuyPosition(
                _vault,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                oppositeOptionTokenId,
                sizeOut,

                tokenOut,
                amountOut,
                executionPrice,
                spotPrice
            );
        }

        return (sizeOut, amountOut, executionPrice);
    }
    
    function pluginClosePosition(
        address _account,
        uint256 _requestIndex,
        uint256 _optionTokenId,
        uint256 _size,
        address _quoteToken,
        uint256 _minAmountOut,
        address _receiver,
        address _vault
    ) external override returns (uint256, uint256) {
        _validatePlugin();
        _validateGasPrice();

        (
            uint16 underlyingAssetIndex,
            uint40 expiry,
            Utils.Strategy strategy,
            uint8 length,
            ,
            uint48[4] memory strikePrices,
            ,
        ) = Utils.parseOptionTokenId(_optionTokenId);
        _validateQuoteToken(strategy, _quoteToken, underlyingAssetIndex, false);

        (
            uint256 executionPrice,
            uint256 amountOut,
            uint256 totalExecutionPriceAmount,
            uint256 utilizedAmount
        ) = IVault(_vault).closePosition(
            _account,
            _requestIndex,
            _optionTokenId,
            _size,
            underlyingAssetIndex,
            strategy,
            strikePrices,
            _quoteToken,
            _receiver
        );
        if (amountOut < _minAmountOut) { revert InsufficientOutput(); }

        IVaultUtils(vaultToVaultUtil[_vault]).updateVaultPositionAfterTrade(expiry, _optionTokenId, _size, true);

        // increase notional volume
        bool isCall = Utils.isCall(strategy);

        uint256 spotPrice = getSpotPriceByUnderlyingAssetIndex(underlyingAssetIndex);

        (, uint8 decimals) = IOptionsMarket(optionsMarket).getUnderlyingAssetByIndex(underlyingAssetIndex);
        
        for (uint256 i = 0; i < length; i++) {
            accumulatedNotionalVolume[underlyingAssetIndex][isCall] += _size * spotPrice / (10 ** decimals);
            emit IncreaseAccumulatedNotionalVolume(underlyingAssetIndex, isCall, _size * spotPrice / (10 ** decimals));
        }

        accumulatedExecutionPrice[underlyingAssetIndex][isCall] += _size * executionPrice / (10 ** decimals);
        emit IncreaseAccumulatedExecutionPrice(underlyingAssetIndex, isCall, _size * executionPrice / (10 ** decimals));

        if (Utils.isBuy(strategy)) {
            emit CloseBuyPosition(
                _account,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                _size,

                _quoteToken,
                amountOut,
                executionPrice,
                spotPrice
            );

            emit OpenBuyPosition(
                _vault,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                _size,

                _quoteToken,
                amountOut,
                executionPrice,
                spotPrice
            );  
        } else {
            emit CloseSellPosition(
                _account,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                _size,

                _quoteToken,
                totalExecutionPriceAmount, // option premium paid by trader
                _quoteToken, // collateral token to give back to trader
                amountOut, // collateral token to give back to trader
                executionPrice,
                spotPrice
            );

            emit OpenSellPosition(
                _vault,
                _requestIndex,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                _size,

                _quoteToken,
                totalExecutionPriceAmount, // option premium received from trader
                _quoteToken, // collateral token paid by olp
                utilizedAmount, // collateral token paid by olp (amountOut + fee)
                executionPrice,
                spotPrice
            );
        }

        return (amountOut, executionPrice);
    }

    function pluginSettlePosition(
        address _account,
        address _quoteToken,
        uint256 _optionTokenId,
        uint256 _size,
        address _receiver
    ) external override returns (uint256, uint256) {
        _validatePlugin();
        _validateGasPrice();

        (
            uint16 underlyingAssetIndex,
            uint40 expiry,
            Utils.Strategy strategy,
            ,
            ,
            uint48[4] memory strikePrices,
            ,
            uint8 vaultIndex
        ) = Utils.parseOptionTokenId(_optionTokenId);
        _validateQuoteToken(strategy, _quoteToken, underlyingAssetIndex, true);

        address vault = getVaultAddressByIndex(vaultIndex);
        bool isAccountVault = _account == vault;

        (uint256 settlePrice, uint256 amountOut, uint256 totalIntrinsicAmount) = IVault(vault).settlePosition(
            _account,
            _size,
            underlyingAssetIndex,
            expiry,
            strategy,
            strikePrices,
            isAccountVault,
            _quoteToken,
            _receiver
        );

        address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(underlyingAssetIndex);
        IOptionsToken(optionsToken).burn(vault, _optionTokenId, _size);

        if (isAccountVault) {
            IVaultUtils(vaultToVaultUtil[vault]).updateVaultPositionAfterTrade(expiry, _optionTokenId, _size, false);
        }

        if (Utils.isBuy(strategy)) {
            emit SettleBuyPosition(
                _account,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                _size,

                _quoteToken,
                amountOut,
                settlePrice
            );
        } else {
            emit SettleSellPosition(
                _account,
                underlyingAssetIndex,
                expiry,
                _optionTokenId,
                _size,

                _quoteToken,
                totalIntrinsicAmount, // total settle payoff received from trader
                _quoteToken, // collateral token to give back to trader
                amountOut, // collateral token to give back to trader
                settlePrice
            );
        }

        return (amountOut, settlePrice);
    }

    function pluginClearPosition(
        uint256[] calldata _optionTokenIds, // only receive optionTokenIds of sell position
        address _vault
    ) external override onlyKeeper {
        uint256 length = _optionTokenIds.length;

        for (uint256 i = 0; i < length;) {
            uint256 optionTokenId = _optionTokenIds[i];

            (
                uint16 underlyingAssetIndex,
                uint40 expiry,
                Utils.Strategy strategy,
                ,
                ,
                uint48[4] memory strikePrices,
                ,
                uint8 vaultIndex
            ) = Utils.parseOptionTokenId(optionTokenId);
            
            address vault = getVaultAddressByIndex(vaultIndex);

            if (expiry <= block.timestamp) { revert ExpiredOptionId(); }
            if (_vault != vault) { revert InvalidVault(); }

            address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(underlyingAssetIndex);
            uint256 oppositeOptionTokenId = Utils.getOppositeOptionTokenId(optionTokenId);

            uint256 size = IERC1155Base(optionsToken).balanceOf(_vault, optionTokenId);
            uint256 sizeOpposite = IERC1155Base(optionsToken).balanceOf(_vault, oppositeOptionTokenId);
            uint256 sizeToClear = size < sizeOpposite ? size : sizeOpposite;

            if (sizeToClear > 0) {
                IVault(_vault).clearPosition(sizeToClear, underlyingAssetIndex, strategy, strikePrices);

                IOptionsToken(optionsToken).burn(_vault, optionTokenId, sizeToClear);
                IOptionsToken(optionsToken).burn(_vault, oppositeOptionTokenId, sizeToClear);

                IVaultUtils vaultUtils = IVaultUtils(vaultToVaultUtil[_vault]);
                vaultUtils.updateVaultPositionAfterTrade(expiry, optionTokenId, sizeToClear, false);
                vaultUtils.updateVaultPositionAfterTrade(expiry, oppositeOptionTokenId, sizeToClear, false);

                emit ClearPosition(_vault, optionsToken, optionTokenId, oppositeOptionTokenId, sizeToClear);
            }

            unchecked { i++; }
        }
    }

    function directPoolDeposit(address _vault, address _token, uint256 _amount) external {
        IERC20(_token).safeTransferFrom(_sender(), _vault, _amount);
        IVault(_vault).directPoolDeposit(_token);
    }

    function swap(address _vault, address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) public override returns (uint256) {
        _validatePlugin();
        
        IERC20(_path[0]).safeTransferFrom(_sender(), _vault, _amountIn);
        uint256 amountOut = _swap(_vault, _path, _minOut, _receiver);
        emit Swap(msg.sender, _vault, _path[0], _path[_path.length - 1], _amountIn, amountOut);
        return amountOut;
    }

    function swapNATToTokens(address _vault, address[] memory _path, uint256 _minOut, address _receiver) external payable {
        _validateNATSwap(true, _path);
        _transferNATToVault(_vault);
        uint256 amountOut = _swap(_vault, _path, _minOut, _receiver);
        emit Swap(msg.sender, _vault, _path[0], _path[_path.length - 1], msg.value, amountOut);
    }

    function swapTokensToNAT(address _vault, address[] memory _path, uint256 _amountIn, uint256 _minOut, address payable _receiver) external {
        _validateNATSwap(false, _path);
        IERC20(_path[0]).safeTransferFrom(_sender(), _vault, _amountIn);
        uint256 amountOut = _swap(_vault, _path, _minOut, address(this));
        _transferOutNAT(amountOut, _receiver);
        emit Swap(msg.sender, _vault, _path[0], _path[_path.length - 1], _amountIn, amountOut);
    }

    function validateOpenPosition(
        uint16 _underlyingAssetIndex,
        uint8 _length,
        bool[4] memory _isBuys,
        bytes32[4] memory _optionIds,
        bool[4] memory _isCalls
    ) external view returns (uint40, uint256, bytes32[4] memory) {
        // 1. Validate option IDs
        uint40 expiry = IOptionsMarket(optionsMarket).validateOptionIds(_underlyingAssetIndex, _length, _optionIds);
        
        // 2. Check trading hours constraint (when opening position, _isOpen = true)
        if (!IOptionsMarket(optionsMarket).isTradingAllowed(_underlyingAssetIndex, block.timestamp, true)) { revert TradingNotAllowed(); }
        
        uint8 vaultIndex = getVaultIndexByTimeGap(uint40(block.timestamp), expiry);
        (uint256 optionTokenId, bytes32[4] memory sortedOptionIds) = IOptionsMarket(optionsMarket).getOptionTokenId(
            _underlyingAssetIndex,
            expiry,
            _length,
            _isBuys,
            _optionIds,
            _isCalls,
            vaultIndex
        );

        (,, Utils.Strategy strategy,,,,,) = Utils.parseOptionTokenId(optionTokenId);
        _validateStrategy(strategy);

        return (expiry, optionTokenId, sortedOptionIds);
    }

    function _validateNATSwap(bool _isNATToTokens, address[] memory _path) private view {
        _validatePlugin();
        _validateNATSupport();
        if (_isNATToTokens ? _path[0] != wnat : _path[_path.length - 1] != wnat) { revert InvalidPath(); }
    }

    function _transferNATToVault(address _vault) private {
        IWNAT(wnat).deposit{value: msg.value}();
        IERC20(wnat).safeTransfer(_vault, msg.value);
    }

    function _transferOutNAT(uint256 _amountOut, address payable _receiver) private {
        IWNAT(wnat).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _swap(address _vault, address[] memory _path, uint256 _minOut, address _receiver) private returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_vault, _path[0], _path[1], _minOut, _receiver);
        }
        if (_path.length == 3) {
            uint256 midOut = _vaultSwap(_vault, _path[0], _path[1], 0, address(this));
            IERC20(_path[1]).safeTransfer(_vault, midOut);
            return _vaultSwap(_vault, _path[1], _path[2], _minOut, _receiver);
        }

        revert InvalidPath();
    }

    function _vaultSwap(address _vault, address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) private returns (uint256) {
        uint256 amountOut;

        address usdg = IVault(_vault).usdg();

        if (_tokenOut == usdg) { // buyUSDG case
            amountOut = IVault(_vault).buyUSDG(_tokenIn, _receiver);
        } else if (_tokenIn == usdg) { // sellUSDG case
            amountOut = IVault(_vault).sellUSDG(_tokenOut, _receiver);
        } else { // swap case
            amountOut = IVault(_vault).swap(_tokenIn, _tokenOut, _receiver);
        }

        if (amountOut < _minOut) { revert InsufficientOutput(); }
        return amountOut;
    }

    function _sender() private view returns (address) {
        return msg.sender;
    }

    function _validatePlugin() private view {
        // msg.sender should be plugin
        if (!plugins[msg.sender]) { revert InvalidPlugin(); }
    }

    function _validateGasPrice() private view {
        if (maxGasPrice == 0) { return; }
        if (tx.gasprice > maxGasPrice) { revert GasPriceExceeded(); }
    }

    function _validateNATSupport() private view {
        if (!isNATSupported) { revert NATNotSupported(); }
    }
    
    // when open position
    // - quoteToken means token that trader should pay
    // - Buy Call: USDC / Buy Put: USDC / Sell Call: UA / Sell Put: USDC
    // - Buy CallSpread: USDC / Buy PutSpread: USDC / Sell CallSpread: USDC / Sell PutSpread: USDC
    //
    // when close position 
    // - quoteToken means token that trader should receive
    // - Buy Call: USDC / Buy Put: USDC / Sell Call: UA / Sell Put: USDC
    // - Buy CallSpread: USDC / Buy PutSpread: USDC / Sell CallSpread: USDC / Sell PutSpread: USDC
    //
    // when settle position
    // - quoteToken means token that trader should receive
    // - Buy Call: UA / Buy Put: USDC / Sell Call: UA / Sell Put: USDC
    // - Buy CallSpread: USDC / Buy PutSpread: USDC / Sell CallSpread: USDC / Sell PutSpread: USDC
    function _validateQuoteToken(
        Utils.Strategy _strategy,
        address _quoteToken,
        uint16 _underlyingAssetIndex,
        bool _isSettle
    ) private view {
        address underlyingAsset = IOptionsMarket(optionsMarket).indexToUnderlyingAsset(_underlyingAssetIndex);
        address mainStableAsset = IOptionsMarket(optionsMarket).mainStableAsset();

        bool isQuoteTokenMatch;

        if (!_isSettle) { // Trade case
            isQuoteTokenMatch = (_strategy == Utils.Strategy.SellCall) ? _quoteToken == underlyingAsset : _quoteToken == mainStableAsset;
        } else { // Settle case
            isQuoteTokenMatch = (_strategy == Utils.Strategy.BuyCall || _strategy == Utils.Strategy.SellCall) ? _quoteToken == underlyingAsset : _quoteToken == mainStableAsset;
        }

        if (!isQuoteTokenMatch) { revert QuoteTokenMismatch(); }
    }

    function _validateStrategy(Utils.Strategy _strategy) private view {
        if (_strategy == Utils.Strategy.NotSupported) { revert NotSupportedStrategy(); }
        uint256 bit = _bit(uint8(_strategy));
        if ((allowedStrategiesMask & bit) == 0) { revert StrategyNotAllowed(); }
    }

    function _bit(uint8 _idx) private pure returns (uint256) {
        return uint256(1) << _idx;
    }
}
