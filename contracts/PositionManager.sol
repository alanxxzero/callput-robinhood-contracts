// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IPositionManager.sol";
import "./tokens/erc1155/interfaces/IERC1155Base.sol";
import "./tokens/erc1155/interfaces/IERC1155Receiver.sol";

import "./BasePositionManager.sol";

import "./proxy/OwnableUpgradeable.sol";

contract PositionManager is BasePositionManager, IPositionManager, IERC1155Receiver, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;

    //////////////////////////////////////////////
    //               POSITION DATA              //
    //////////////////////////////////////////////
    
    struct OpenPositionRequest {
        address account;                    // trader's address
        uint16 underlyingAssetIndex;        // underlying asset index
        bytes32[4] optionIds;               // ID of each option
        uint40 expiry;                      // expiry of the option
        uint256 optionTokenId;              // ID of the option token         
        uint256 minSize;                    // minimum quantity of option tokens (variable value)
        address[] path;                     // swap path
        uint256 amountIn;                   // amount of payment token (fixed value)
        uint256 minOutWhenSwap;             // minimum quantity of tokens desired when swapping
        bool isDepositedInNAT;              // whether the payment token is NAT
        uint40 blockTime;                   // block time at the moment of request
        RequestStatus status;               // request status
        uint256 sizeOut;                    // quantity of the executed option token
        uint256 executionPrice;             // price of the executed option token
        uint40 processBlockTime;            // block time at the moment of execution
        uint256 amountOut;                  // quantity of the premium when sold option
    }

    struct ClosePositionRequest {
        address account;                    // trader's address
        uint16 underlyingAssetIndex;        // underlying asset index
        uint40 expiry;                      // expiry of the option
        uint256 optionTokenId;              // ID of the option token
        uint256 size;                       // quantity of the option token (fixed value)
        address[] path;                     // swap path
        uint256 minAmountOut;               // minimum quantity of payout token (variable value)
        uint256 minOutWhenSwap;             // minimum quantity of tokens desired when swapping
        bool withdrawNAT;                   // whether the payout token is NAT
        uint40 blockTime;                   // block time at the moment of request
        RequestStatus status;               // request status
        uint256 amountOut;                  // quantity of the payout token
        uint256 executionPrice;             // price of the executed option token
        uint40 processBlockTime;            // block time at the moment of execution
    }

    
    /* =============== VARIABLES ============== */
    uint256 public executionFee;
    uint40 public override maxTimeDelay;
    uint40 public override positionDeadlineBuffer;

    uint256 public override positionRequestKeysStart;

    bytes32[] public override positionRequestKeys;
    bool[] public override positionRequestTypes;

    mapping(address => uint256) internal openPositionsIndex;
    mapping(bytes32 => OpenPositionRequest) public override openPositionRequests;

    mapping(address => uint256) internal closePositionsIndex;
    mapping(bytes32 => ClosePositionRequest) public override closePositionRequests;

    uint256 public copyTradeFeeRebateRate;
    mapping(uint256 => address) public leadTrader; // requestIndex to leadTrader

    /* ====== APPEND-ONLY (M3-2, slot 167+) ==== */
    // Retired fee/claim slots. Never read, write or reuse; preserve the frozen proxy layout.
    mapping(bytes32 => uint256) private requestExecutionFee;
    uint256 private pendingFeeTotal;
    mapping(address => mapping(address => uint256)) private unclaimed;
    mapping(address => mapping(address => mapping(uint256 => uint256))) private unclaimedPositions;
    mapping(address => uint256) private parkedTotal;
    mapping(address => mapping(uint256 => uint256)) private parkedPositionTotal;

    /* =============== ERRORS ================= */
    error InvalidFeeRebateRate();
    error InvalidExecutionFee();
    error InvalidPathLength();
    error InvalidPath();
    error InvalidNatWithdrawPath();
    error InvalidAmountIn();
    error InvalidLeadTrader();
    error OpenDeadlineBuffer();
    error InvalidSize();
    error InsufficientOptionBalance();
    error CloseDeadlineBuffer();
    error TradingNotAllowed();
    error InvalidQueueLength();
    error InvalidSender();
    error RequestExpired();
    error InvalidExpiry();
    error MainStableAssetNotSet();
    error OptionExpired();
    error NotRecoverable();
    error NotExpired();

    /* =============== EVENTS ================= */
    event CreateOpenPosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        bytes32[4] optionIds,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 minSize,
        address[] path,
        uint256 amountIn,
        uint256 minOutWhenSwap,
        uint256 index,
        uint256 queueIndex,
        uint256 gasPrice,
        uint40 blockTime
    );

    event ExecuteOpenPosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,
        address[] path,
        uint256 amountIn,
        uint256 executionPrice,
        uint40 timeGap
    );

    event CancelOpenPosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        bytes32[4] optionIds,
        uint40 indexed expiry,
        uint256 optionTokenId,
        address[] path,
        uint256 amountIn,
        uint40 timeGap
    );

    event CreateClosePosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,
        address[] path,
        uint256 minAmountOut,
        uint256 minOutWhenSwap,
        uint256 index,
        uint256 queueIndex,
        uint40 blockTime
    );

    event ExecuteClosePosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,
        address[] path,
        uint256 amountOut,
        uint256 executionPrice,
        uint40 timeGap
    );

    event CancelClosePosition(
        address indexed account,
        uint16 indexed underlyingAssetIndex,
        uint40 indexed expiry,
        uint256 optionTokenId,
        uint256 size,
        address[] path,
        uint40 timeGap
    );

    event RecoverExpiredRequest(address indexed account, bytes32 indexed key, bool indexed isOpen, uint256 executionFee);

    event GenerateRequestKey(address indexed account, bytes32 indexed key, bool indexed isOpen);
    event SetExecutionFee(uint256 indexed executionFee);
    event SetMaxTimeDelay(uint40 indexed maxTimeDelay);
    event SetPositionDeadlineBuffer(uint40 indexed positionDeadlineBuffer);
    event SetCopyTradeFeeRebateRate(uint40 indexed copyTradeFeeRebateRate);

    //////////////////////////////////////////////
    //              INITIALIZATION              //
    //////////////////////////////////////////////

    /* =============== INITIALIZE ============= */
    function initialize(
        address _optionsMarket,
        address _controller,
        address _wnat,
        IOptionsAuthority _authority,
        uint256 _executionFee
    ) public initializer {
        __Ownable_init();
        __BasePositionManager_init__(
            _optionsMarket,
            _controller,
            _wnat,
            _authority
        );

        executionFee = _executionFee;

        maxTimeDelay = 180; // position request will be cancelled if the request is not executed within maxTimeDelay
        positionDeadlineBuffer = 1800; // equal to 30 minutes
        copyTradeFeeRebateRate = 3000;
    }

    //////////////////////////////////////////////
    //              OPTION LOGICS               //
    //////////////////////////////////////////////

    /* =============== FUNCTIONS ============== */

    function setExecutionFee(uint256 _executionFee) external onlyAdmin {
        executionFee = _executionFee;
        emit SetExecutionFee(_executionFee);
    }

    function setMaxTimeDelay(uint40 _maxTimeDelay) external onlyAdmin {
        maxTimeDelay = _maxTimeDelay;
        emit SetMaxTimeDelay(_maxTimeDelay);
    }

    function setPositionDeadlineBuffer(uint40 _positionDeadlineBuffer) external onlyAdmin {
        positionDeadlineBuffer = _positionDeadlineBuffer;
        emit SetPositionDeadlineBuffer(_positionDeadlineBuffer);
    }

    function setCopyTradeFeeRebateRate(uint40 _copyTradeFeeRebateRate) external onlyAdmin {
        if (_copyTradeFeeRebateRate > 10000) revert InvalidFeeRebateRate();
        copyTradeFeeRebateRate = _copyTradeFeeRebateRate;
        emit SetCopyTradeFeeRebateRate(_copyTradeFeeRebateRate);
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

    //////////////////////////////////////////////
    //              OPEN POSITIONS              //
    //////////////////////////////////////////////

    /*
     * path
     * - the length of _path is either 1 or 2
     * - path[0] signifies the address of the token paid
     * - path[length-1] signifies the address of the final token to be paid
     * - amountIn signifies the quantity of the token at path[0].
     * 
     * - conclusion,
     *   - if the length of path is 1, then the address of the token paid and the final token to be paid are the same,
     *   - if the length of path is 2, then the address of the token paid and the final token to be paid are different, implying a swap occurs.
     *
     * when the length of path is 1,
     * - Buy Call, Buy Put, Buy Call Spread, Buy Put Spread: [USDC] => option premium to pay
     * - Sell Call: [UnderlyingAsset] => collateral to pay
     * - Sell Put, Sell Call Spread, Sell Put Spread: [USDC] => collateral to pay
     * 
     * when the length of path is 2,
     * - Buy Call, Buy Put, Buy Call Spread, Buy Put Spread: [Token, USDC]
     * - Sell Call: [Token, UnderlyingAsset]
     * - Sell Put, Sell Call Spread, Sell Put Spread: [Token, USDC]
     * 
     * As a result,
     * - When the length of path is 1, path[0] is the address of the token trader actually pays
     * - When the length of path is 1, path[0] is the adress of the token protocol should receive
     * - When the length of path is 2, path[0] is the address of the token trader actually pays
     * - When the length of path is 2, path[1] is the address of the token protocol should receive
     */
    function createOpenPosition(
        uint16 _underlyingAssetIndex,           // underlying asset index
        uint8 _length,                          // number of types of options
        bool[4] memory _isBuys,                 // trade type for each option
        bytes32[4] memory _optionIds,           // ID of each option
        bool[4] memory _isCalls,                // exercise method for each option
        uint256 _minSize,                       // minimum quantity of option tokens (variable value)
        address[] memory _path,                 // swap path
        uint256 _amountIn,                      // amount of payment token (fixed value)
        uint256 _minOutWhenSwap,                // minimum quantity of tokens desired when swapping
        address _leadTrader
    ) external payable nonReentrant returns (bytes32) {
        if (msg.value != executionFee) revert InvalidExecutionFee();
        if (_path.length != 1 && _path.length != 2) revert InvalidPathLength();
        if (_amountIn == 0) revert InvalidAmountIn();
        if (_leadTrader == msg.sender) revert InvalidLeadTrader();
        
        _transferInNAT(); // get executionFee
        IController(controller).pluginERC20Transfer(_path[0], msg.sender, address(this), _amountIn); // get payment token
        
        (uint40 expiry, uint256 optionTokenId, bytes32[4] memory sortedOptionIds) = IController(controller).validateOpenPosition(
            _underlyingAssetIndex,
            _length,
            _isBuys,
            _optionIds,
            _isCalls  
        );

        uint256 blockTime = uint40(block.timestamp);
        if (blockTime + positionDeadlineBuffer >= expiry) revert OpenDeadlineBuffer();

        return _createOpenPosition(
            msg.sender,
            _underlyingAssetIndex,
            sortedOptionIds,
            expiry,
            optionTokenId,
            _minSize,
            _path,
            _amountIn,
            _minOutWhenSwap,
            false,
            _leadTrader
        );
    }

    // Native principal is wrapped together with the execution fee. Controller decides support.
    function createOpenPositionNAT(
        uint16 _underlyingAssetIndex,
        uint8 _length,
        bool[4] memory _isBuys,
        bytes32[4] memory _optionIds,
        bool[4] memory _isCalls,
        uint256 _minSize,
        address[] memory _path,
        uint256 _minOutWhenSwap,
        address _leadTrader
    ) external payable nonReentrant returns (bytes32) {
        IController(controller).validateNATSupport();

        if (msg.value < executionFee) revert InvalidExecutionFee();
        if (_path.length != 1 && _path.length != 2) revert InvalidPathLength();
        if (_path[0] != wnat) revert InvalidPath();
        if (_leadTrader == msg.sender) revert InvalidLeadTrader();

        _transferInNAT();
        uint256 amountIn;
        unchecked {
            amountIn = msg.value - executionFee;
        }
        if (amountIn == 0) revert InvalidAmountIn();

        (uint40 expiry, uint256 optionTokenId, bytes32[4] memory sortedOptionIds) = IController(controller).validateOpenPosition(
            _underlyingAssetIndex,
            _length,
            _isBuys,
            _optionIds,
            _isCalls
        );

        return _createOpenPosition(
            msg.sender,
            _underlyingAssetIndex,
            sortedOptionIds,
            expiry,
            optionTokenId,
            _minSize,
            _path,
            amountIn,
            _minOutWhenSwap,
            true,
            _leadTrader
        );
    }

    //////////////////////////////////////////////
    //              CLOSE POSITIONS             //
    //////////////////////////////////////////////

    /*
     * path
     * - the length of path is either 1 or 2
     * - path[0] signifies the address of the token to be received
     * - path[length-1] signifies the address of the final token to be received
     * 
     * - conclusion,
     *   - if the length of path is 1, then the address of the token to be received and the final token to be received are the same.
     *   - if the length of path is 2, then the address of the token to be received and the final token to be received are different, and a swap occurs.
     * 
     *  when the length of path is 1,
     * - Buy Call, Buy Put, Buy Call Spread, Buy Put Spread: [USDC] => option premium to receive
     * - Sell Call: [UnderlyingAsset] => collateral to receive
     * - Sell Put, Sell Call Spread, Sell Put Spread: [USDC] => collateral to receive
     * 
     * when the length of path is 2,
     * - Buy Call, Buy Put, Buy Call Spread, Buy Put Spread: [USDC, Token]
     * - Sell Call: [UnderlyingAsset, Token]
     * - Sell Put, Sell Call Spread, Sell Put Spread: [USDC, Token]
     * 
     * As a result,
     * - When the length of path is 1, path[0] is the address of the token protocol should pay
     * - When the length of path is 1, path[0] is the address of the token trader actually receives
     * - When the length of path is 2, path[0] is the address of the token protocol should pay
     * - When the length of path is 2, path[1] is the address of the token trader actually receives
     */
    function createClosePosition(
        uint16 _underlyingAssetIndex,
        uint256 _optionTokenId,
        uint256 _size,
        address[] memory _path,
        uint256 _minAmountOut,
        uint256 _minOutWhenSwap,
        bool _withdrawNAT
    ) external payable nonReentrant returns (bytes32) {
        if (msg.value != executionFee) revert InvalidExecutionFee();
        if (_path.length != 1 && _path.length != 2) revert InvalidPathLength();
        if (_size == 0) revert InvalidSize();
        
        if (_withdrawNAT) {
            IController(controller).validateNATSupport();
            if (_path[_path.length - 1] != wnat) revert InvalidNatWithdrawPath();
        }

        address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(_underlyingAssetIndex);
        if (IERC1155Base(optionsToken).balanceOf(msg.sender, _optionTokenId) < _size) revert InsufficientOptionBalance();

        uint40 expiry = Utils.getExpiryByOptionTokenId(_optionTokenId);
        uint40 blockTime = uint40(block.timestamp);
        if (blockTime + positionDeadlineBuffer >= expiry) revert CloseDeadlineBuffer();

        // Check trading hours constraint (when closing position, _isOpen = false)
        if (!IOptionsMarket(optionsMarket).isTradingAllowed(_underlyingAssetIndex, blockTime, false)) revert TradingNotAllowed();

        _transferInNAT(); // receive executionFee
        IController(controller).pluginERC1155Transfer(optionsToken, msg.sender, address(this), _optionTokenId, _size); // receive option token

        return _createClosePosition(
            msg.sender,
            _underlyingAssetIndex,
            expiry,
            _optionTokenId,
            _size,
            _path,
            _minAmountOut,
            _minOutWhenSwap,
            _withdrawNAT
        );
    }

    //////////////////////////////////////////////
    //  EXECUTE REQUESTED POSITIONS             //
    //////////////////////////////////////////////

    function executePositions(uint256 _endIndex, address payable _executionFeeReceiver) external override onlyFastPriceFeed {
        uint256 index = positionRequestKeysStart;
        uint256 keysLength = positionRequestKeys.length;
        uint256 typesLength = positionRequestTypes.length;
        if (keysLength != typesLength) revert InvalidQueueLength();

        if (index >= keysLength) { return; }

        if (_endIndex > keysLength) {
            _endIndex = keysLength;
        }

        while (index < _endIndex) {
            (bytes32 key, bool isOpenPosition) = getPositionRequestInfo(index);

            bool shouldContinue = true;
            bool shouldIncreaseIndex = true;

            if (isOpenPosition) {
                try this.executeOpenPosition(index, key, _executionFeeReceiver) returns (bool _wasExecuted) {
                    if (!_wasExecuted) { 
                        shouldContinue = false;
                        shouldIncreaseIndex = false;
                    }
                } catch {
                    try this.cancelOpenPosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                        if (!_wasCancelled) {
                            shouldContinue = false;
                            shouldIncreaseIndex = false;
                        }
                    } catch {
                        // To prevent getting stuck, IncreaseIndex is necessary, but Continue is false due to Risk Premium.
                        shouldContinue = false;
                    }
                }
            } else {
                try this.executeClosePosition(index, key, _executionFeeReceiver) returns (bool _wasExecuted) {
                    if (!_wasExecuted) {
                        shouldContinue = false;
                        shouldIncreaseIndex = false;
                    }
                } catch {
                    try this.cancelClosePosition(key, _executionFeeReceiver) returns (bool _wasCancelled) {
                        if (!_wasCancelled) {
                            shouldContinue = false;
                            shouldIncreaseIndex = false;
                        }
                    } catch {
                        // To prevent getting stuck, IncreaseIndex is necessary, but Continue is false due to Risk Premium.
                        shouldContinue = false;
                    }
                }
            }

            if (shouldIncreaseIndex) {
                index++;
                positionRequestKeysStart = index; // Update immediately to prevent reentrancy
            }
            
            if (!shouldContinue) {
                break;
            }
        }
    }

    function executeOpenPosition(uint256 _requestIndex, bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool isExecuted) {
        if (msg.sender != address(this)) revert InvalidSender();
        
        OpenPositionRequest storage request = openPositionRequests[_key];
        if (request.status == RequestStatus.Executed || request.status == RequestStatus.Cancelled) { return true; }

        uint40 blockTime = uint40(block.timestamp);
        if (request.blockTime + maxTimeDelay < blockTime) revert RequestExpired();

        (uint8 length, bool[4] memory isBuys, bool[4] memory isCalls) = _parseLegs(request.optionTokenId);
        (uint40 expiry,,) = IController(controller).validateOpenPosition(
            request.underlyingAssetIndex,
            length,
            isBuys,
            request.optionIds,
            isCalls
        );
        if (expiry != request.expiry) revert InvalidExpiry();

        address vault = IController(controller).getVaultAddressByOptionTokenId(request.optionTokenId);

        uint256 amountIn = request.amountIn;
        if (request.path.length > 1) {
            amountIn = _swap(vault, request.path, request.amountIn, request.minOutWhenSwap, address(this));
        }
        IERC20(request.path[request.path.length - 1]).safeTransfer(vault, amountIn);

        (uint256 sizeOut, uint256 amountOut, uint256 executionPrice) = IController(controller).pluginOpenPosition(
            request.account,
            _requestIndex,
            request.path[request.path.length - 1],
            request.optionTokenId,
            request.minSize,
            address(this),
            vault
        );

        if (sizeOut > 0) {
            address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(request.underlyingAssetIndex);
            IERC1155Base(optionsToken).safeTransferFrom(address(this), request.account, request.optionTokenId, sizeOut, "");
        }

        if (amountOut > 0) {
            (address mainStableAsset,) = IOptionsMarket(optionsMarket).getMainStableAsset();
            if (mainStableAsset == address(0)) revert MainStableAssetNotSet();
            IERC20(mainStableAsset).safeTransfer(request.account, amountOut);
        }

        uint256 fee = executionFee;
        if (fee != 0) _transferOutNATWithGasLimitFallbackToWnat(fee, _executionFeeReceiver);

        request.status = RequestStatus.Executed;
        request.sizeOut = sizeOut;
        request.executionPrice = executionPrice;
        request.processBlockTime = blockTime;
        request.amountOut = amountOut;
        
        emit ExecuteOpenPosition(
            request.account,
            request.underlyingAssetIndex,
            expiry,
            request.optionTokenId,
            sizeOut,
            request.path,
            amountIn,
            executionPrice,
            blockTime - request.blockTime
        );

        return true;
    }

    function cancelOpenPosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        if (msg.sender != address(this)) revert InvalidSender();

        OpenPositionRequest storage request = openPositionRequests[_key];
        // if the request was already executed or cancelled, return true so that the executeIncreasePositions loop will continue executing the next request
        if (request.status == RequestStatus.Executed || request.status == RequestStatus.Cancelled) { return true; }

        uint40 blockTime = uint40(block.timestamp);

        bool shouldCancel = request.blockTime <= blockTime;
        if (!shouldCancel) { return false; }

        if (request.isDepositedInNAT) {
            _transferOutNATWithGasLimitFallbackToWnat(request.amountIn, payable(request.account));
        } else {
            IERC20(request.path[0]).safeTransfer(request.account, request.amountIn);
        }
        
        uint256 fee = executionFee;
        if (fee != 0) _transferOutNATWithGasLimitFallbackToWnat(fee, _executionFeeReceiver);

        request.status = RequestStatus.Cancelled;
        request.processBlockTime = blockTime;

        emit CancelOpenPosition(
            request.account,
            request.underlyingAssetIndex,
            request.optionIds,
            request.expiry,
            request.optionTokenId,
            request.path,
            request.amountIn,
            blockTime - request.blockTime
        );

        return true;
    }

    function executeClosePosition(uint256 _requestIndex, bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool isExecuted) {
        if (msg.sender != address(this)) revert InvalidSender();

        ClosePositionRequest storage request = closePositionRequests[_key];
        if (request.status == RequestStatus.Executed || request.status == RequestStatus.Cancelled) { return true; }

        uint40 blockTime = uint40(block.timestamp);
        if (request.expiry <= blockTime) revert OptionExpired();
        if (request.blockTime + maxTimeDelay < blockTime) revert RequestExpired();

        // Check trading hours constraint (when closing position, _isOpen = false)
        if (!IOptionsMarket(optionsMarket).isTradingAllowed(request.underlyingAssetIndex, blockTime, false)) revert TradingNotAllowed();

        address vault = IController(controller).getVaultAddressByOptionTokenId(request.optionTokenId);
        
        address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(request.underlyingAssetIndex);
        
        IERC1155Base(optionsToken).safeTransferFrom(address(this), vault, request.optionTokenId, request.size, "");

        (uint256 amountOut, uint256 executionPrice) = IController(controller).pluginClosePosition(
            request.account,
            _requestIndex,
            request.optionTokenId,
            request.size,
            request.path[0],
            request.minAmountOut,
            address(this),
            vault
        );
        
        if (amountOut > 0) {
            if (request.path.length > 1) {
                amountOut = _swap(vault, request.path, amountOut, request.minOutWhenSwap, address(this));
            }

            if (request.withdrawNAT) {
                _transferOutNATWithGasLimitFallbackToWnat(amountOut, payable(request.account));
            } else {
                IERC20(request.path[request.path.length - 1]).safeTransfer(request.account, amountOut);
            }
        }

        uint256 fee = executionFee;
        if (fee != 0) _transferOutNATWithGasLimitFallbackToWnat(fee, _executionFeeReceiver);
        
        request.status = RequestStatus.Executed;
        request.amountOut = amountOut;
        request.executionPrice = executionPrice;
        request.processBlockTime = blockTime;

        emit ExecuteClosePosition(
            request.account,
            request.underlyingAssetIndex,
            request.expiry,
            request.optionTokenId,
            request.size,
            request.path,
            amountOut,
            executionPrice,
            blockTime - request.blockTime
        );

        return true;
    }

    function cancelClosePosition(bytes32 _key, address payable _executionFeeReceiver) public nonReentrant returns (bool) {
        if (msg.sender != address(this)) revert InvalidSender();

        ClosePositionRequest storage request = closePositionRequests[_key];
        if (request.status == RequestStatus.Executed || request.status == RequestStatus.Cancelled) { return true; }

        uint40 blockTime = uint40(block.timestamp);

        bool shouldCancel = request.blockTime <= blockTime;
        if (!shouldCancel) { return false; }

        address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(request.underlyingAssetIndex);

        IERC1155Base(optionsToken).safeTransferFrom(address(this), request.account, request.optionTokenId, request.size, "");

        uint256 fee = executionFee;
        if (fee != 0) _transferOutNATWithGasLimitFallbackToWnat(fee, _executionFeeReceiver);

        request.status = RequestStatus.Cancelled;
        request.processBlockTime = blockTime;

        emit CancelClosePosition(
            request.account,
            request.underlyingAssetIndex,
            request.expiry,
            request.optionTokenId,
            request.size,
            request.path,
            blockTime - request.blockTime
        );

        return true;
    }
    
    //////////////////////////////////////////////
    //        EXPIRED REQUEST RECOVERY          //
    //////////////////////////////////////////////

    /*
     * Keeper clean-up for a request the normal queue never settled: `executePositions` skips a
     * request whose execute *and* cancel both revert (see the catch blocks above), leaving it
     * `Pending` forever with the trader's amountIn / option lot held by this contract.
     *
     * Principal/positions always go to `request.account`. The registered position keeper calling
     * recovery receives the global execution fee, just as in normal execution/cancellation.
     * The request is terminal afterwards (`Cancelled`) - there is no re-execution; the trader
     * simply submits a new request.
     *
     * Queue integrity: the cursor is untouched. If the request is still in front of
     * `positionRequestKeysStart`, `executeOpenPosition`/`executeClosePosition` will later see
     * `Cancelled`, return true before doing any transfer, and the cursor advances as usual.
     *
     * Every return is atomic. A failed transfer reverts the cancellation and leaves the request
     * Pending so the same recovery can be retried. There is no deferred claim balance.
     */
    function recoverExpiredRequest(bytes32 _key, bool _isOpen) external onlyPositionKeeper nonReentrant {
        if (_isOpen) {
            _recoverOpen(_key);
        } else {
            _recoverClose(_key);
        }
    }

    function _recoverOpen(bytes32 _key) private {
        OpenPositionRequest storage request = openPositionRequests[_key];
        address account = request.account;
        // account == 0 also rejects a key that was never created (default status is Pending)
        if (account == address(0) || request.status != RequestStatus.Pending) revert NotRecoverable();
        if (uint256(request.blockTime) + maxTimeDelay >= block.timestamp) revert NotExpired();

        request.status = RequestStatus.Cancelled;
        request.processBlockTime = uint40(block.timestamp);

        uint256 fee = executionFee;
        if (request.isDepositedInNAT) {
            _transferOutNATWithGasLimitFallbackToWnat(request.amountIn, payable(account));
        } else {
            IERC20(request.path[0]).safeTransfer(account, request.amountIn);
        }
        if (fee != 0) _transferOutNATWithGasLimitFallbackToWnat(fee, payable(msg.sender));

        emit RecoverExpiredRequest(account, _key, true, fee);
    }

    function _recoverClose(bytes32 _key) private {
        ClosePositionRequest storage request = closePositionRequests[_key];
        address account = request.account;
        if (account == address(0) || request.status != RequestStatus.Pending) revert NotRecoverable();
        if (uint256(request.blockTime) + maxTimeDelay >= block.timestamp) revert NotExpired();

        request.status = RequestStatus.Cancelled;
        request.processBlockTime = uint40(block.timestamp);

        uint256 fee = executionFee;
        address optionsToken = IOptionsMarket(optionsMarket).getOptionsTokenByIndex(request.underlyingAssetIndex);
        uint256 size = request.size;
        IERC1155Base(optionsToken).safeTransferFrom(address(this), account, request.optionTokenId, size, "");
        if (fee != 0) _transferOutNATWithGasLimitFallbackToWnat(fee, payable(msg.sender));

        emit RecoverExpiredRequest(account, _key, false, fee);
    }

    // lean decode of the leg fields of an option token id (see Utils.formatOptionTokenId for the bit layout).
    // the id was minted by Controller at request creation and validateOpenPosition re-validates it right after,
    // so the strategy check of Utils.parseOptionTokenId is not repeated here.
    function _parseLegs(uint256 _optionTokenId) private pure returns (uint8 length, bool[4] memory isBuys, bool[4] memory isCalls) {
        length = uint8((_optionTokenId >> 194) & 0x3) + 1; // 2 bits for length
        for (uint256 i = 0; i < 4;) {
            isBuys[i] = ((_optionTokenId >> (193 - i * 48)) & 0x1) != 0; // 1 bit each
            isCalls[i] = ((_optionTokenId >> (146 - i * 48)) & 0x1) != 0; // 1 bit each
            unchecked { i++; }
        }
    }

    function getRequestKey(address _account, uint256 _index, bool _isOpenPosition) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _index, _isOpenPosition));
    }

    function getRequestQueueLengths() external view override returns (uint256, uint256, uint256) {
        return (
            positionRequestKeysStart,
            positionRequestKeys.length,
            positionRequestTypes.length
        );
    }

    function getOpenPositionRequestPath(bytes32 _key) public view override returns (address[] memory) {
        return openPositionRequests[_key].path;
    }

    function getClosePositionRequestPath(bytes32 _key) public view override returns (address[] memory) {
        return closePositionRequests[_key].path;
    }

    function getPositionRequestInfo(uint256 _requestIndex) public view override returns (bytes32, bool) {
        bytes32 key = positionRequestKeys[_requestIndex];           // positionRequestKeys contains openPositionRequests and closePositionRequests
        bool isOpenPosition = positionRequestTypes[_requestIndex];  // positionRequestTypes is used to distinguish between open and close
        return (key, isOpenPosition);
    }

    function _createOpenPosition(
        address _account,
        uint16 _underlyingAssetIndex,
        bytes32[4] memory _optionIds,
        uint40 _expiry,
        uint256 _optionTokenId,
        uint256 _minSize,
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOutWhenSwap,
        bool _isDepositedInNAT,
        address _leadTrader
    ) internal returns (bytes32) {
        uint40 blockTime = uint40(block.timestamp);

        OpenPositionRequest memory request = OpenPositionRequest({
            account: _account,
            underlyingAssetIndex: _underlyingAssetIndex,
            optionIds: _optionIds,
            expiry: _expiry,
            optionTokenId: _optionTokenId,
            minSize: _minSize,
            path: _path,
            amountIn: _amountIn,
            minOutWhenSwap: _minOutWhenSwap,
            isDepositedInNAT: _isDepositedInNAT,
            blockTime: blockTime,
            status: RequestStatus.Pending,
            sizeOut: 0,
            executionPrice: 0,
            processBlockTime: 0,
            amountOut: 0
        });

        (uint256 index, bytes32 requestKey) = _storeOpenPositionRequest(request);

        leadTrader[positionRequestKeys.length - 1] = _leadTrader;

        emit CreateOpenPosition(
            _account,
            _underlyingAssetIndex,
            _optionIds,
            _expiry,
            _optionTokenId,
            _minSize,
            _path,
            _amountIn,
            _minOutWhenSwap,
            index,
            positionRequestKeys.length - 1,
            tx.gasprice,
            blockTime
        );

        return requestKey;
    }

    function _createClosePosition(
        address _account,
        uint16 _underlyingAssetIndex,
        uint40 _expiry,
        uint256 _optionTokenId,
        uint256 _size,
        address[] memory _path,
        uint256 _minAmountOut,
        uint256 _minOutWhenSwap,
        bool _withdrawNAT
    ) internal returns (bytes32) {
        uint40 blockTime = uint40(block.timestamp);

        ClosePositionRequest memory request = ClosePositionRequest({
            account: _account,
            underlyingAssetIndex: _underlyingAssetIndex,
            expiry: _expiry,
            optionTokenId: _optionTokenId,
            size: _size,
            path: _path,
            minAmountOut: _minAmountOut,
            minOutWhenSwap: _minOutWhenSwap,
            withdrawNAT: _withdrawNAT,
            blockTime: blockTime,
            status: RequestStatus.Pending,
            amountOut: 0,
            executionPrice: 0,
            processBlockTime: 0
        });

        (uint256 index, bytes32 requestKey) = _storeClosePositionRequest(request);

        emit CreateClosePosition(
            _account,
            _underlyingAssetIndex,
            _expiry,
            _optionTokenId,
            _size,
            _path,
            _minAmountOut,
            _minOutWhenSwap,
            index,
            positionRequestKeys.length - 1,
            blockTime
        );

        return requestKey;
    }

    function _storeOpenPositionRequest(OpenPositionRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = openPositionsIndex[account] + 1;
        openPositionsIndex[account] = index; // number of open position orders requested by the trader so far
        bytes32 key = getRequestKey(account, index, true); // create a key based on the trader's address and number of orders

        openPositionRequests[key] = _request; // link the request based on the created key

        positionRequestKeys.push(key); // array for storing created keys
        positionRequestTypes.push(true); // array for storing the position types of the created keys

        emit GenerateRequestKey(account, key, true);

        return (index, key);
    }

    function _storeClosePositionRequest(ClosePositionRequest memory _request) internal returns (uint256, bytes32) {
        address account = _request.account;
        uint256 index = closePositionsIndex[account] + 1;
        closePositionsIndex[account] = index;
        bytes32 key = getRequestKey(account, index, false);

        closePositionRequests[key] = _request;

        positionRequestKeys.push(key);
        positionRequestTypes.push(false);

        emit GenerateRequestKey(account, key, false);

        return (index, key);
    }

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
