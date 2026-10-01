// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../libraries/Address.sol";

import "../tokens/interfaces/IERC20.sol";
import "../tokens/libraries/SafeERC20.sol";
import "../tokens/interfaces/IWNAT.sol";

import "./interfaces/IOlpQueue.sol";
import "./interfaces/IRewardRouterV2.sol";
import "./interfaces/IRewardTracker.sol";

import "../interfaces/IOlpManager.sol";
import "../interfaces/IController.sol";

import "../AuthorityUtil.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../proxy/ReentrancyGuardUpgradeable.sol";

contract OlpQueue is IOlpQueue, OwnableUpgradeable, ReentrancyGuardUpgradeable, AuthorityUtil {
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 private constant UNINITIALIZED_INDEX = type(uint256).max;

    address public wnat;
    address public rewardRouter;
    address public rewardTracker;

    QueueAction[] private _queue;
    uint256 private _lastProcessedIndex;

    uint256 public natTransferGasLimit;

    event SetNatTransferGasLimit(uint256 indexed natTransferGasLimit);
    event EnqueuedMintAndStake(uint256 indexed index, ActionType indexed actionType, address indexed user, address token, uint256 amount, uint256 minOut, address receiver, bool isNative);
    event EnqueuedUnstakeAndRedeem(uint256 indexed index, ActionType indexed actionType, address indexed user, address tokenOut, uint256 olpAmount, uint256 minOut, address receiver, bool isNative);
    event ProcessedQueueAction(uint256 indexed index, ActionType indexed actionType, address indexed user, uint256 amountOut, uint256 olpPrice);
    event CancelledQueueAction(uint256 indexed index, ActionType indexed actionType, address indexed user, CancelMode cancelMode);

    modifier onlyRewardRouter() {
        require(msg.sender == address(rewardRouter), "OlpQueue: only reward router");
        _;
    }

    receive() external payable {}

    function initialize(
        address _wnat,
        address _rewardRouter,
        address _rewardTracker,
        IOptionsAuthority _authority
    ) external initializer {
        require(_rewardRouter != address(0), "OlpQueue: invalid reward router");
        
        __Ownable_init();
        __ReentrancyGuard_init();
        __AuthorityUtil_init__(_authority);

        wnat = _wnat;
        rewardRouter = _rewardRouter;
        rewardTracker = _rewardTracker;

        _lastProcessedIndex = UNINITIALIZED_INDEX;

        natTransferGasLimit = 500_000;
    }

    function setNatTransferGasLimit(uint256 _natTransferGasLimit) external onlyAdmin {
        natTransferGasLimit = _natTransferGasLimit;
        emit SetNatTransferGasLimit(_natTransferGasLimit);
    }

    function forceReleaseUnstakeForAccount(address _account, uint256 _amount) external onlyAdmin {
        IRewardTracker(rewardTracker).releaseUnstakeForAccount(_account, _amount);
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

    function queue(uint256 _index) external view override returns (QueueAction memory) {
        require(_index < _queue.length, "OlpQueue: index out of bounds");
        return _queue[_index];
    }

    function queueLength() external view override returns (uint256) {
        return _queue.length;
    }

    function lastProcessedIndex() external view override returns (uint256) {
        return _lastProcessedIndex;
    }

    function hasPendingQueue() external view override returns (bool) {
        if (_queue.length == 0) return false;
        return _getNextProcessIndex() < _queue.length;
    }

    function enqueueMintAndStake(
        address _user,
        address _token,
        uint256 _amount,
        uint256 _minOut,
        address _receiver,
        bool _isNative
    ) external override onlyRewardRouter returns (uint256) {
        // As this function is called by RewardRouter, the parameters are always valid
        
        address token = _isNative ? IRewardRouterV2(rewardRouter).wnat() : _token;
        
        uint256 queueIndex = _enqueue(QueueAction({
            actionType: ActionType.MINT_AND_STAKE,
            user: _user,
            token: token,
            amount: _amount,
            minOut: _minOut,
            receiver: payable(_receiver),
            isNative: _isNative,
            blockTime: uint40(block.timestamp),
            status: ProcessStatus.ENQUEUED,
            amountOut: 0,
            processBlockTime: 0
        }));

        emit EnqueuedMintAndStake(queueIndex, ActionType.MINT_AND_STAKE, _user, _token, _amount, _minOut, _receiver, _isNative);

        return queueIndex;
    }

    function enqueueUnstakeAndRedeem(
        address _user,
        address _tokenOut,
        uint256 _olpAmount,
        uint256 _minOut,
        address _receiver,
        bool _isNative
    ) external override onlyRewardRouter returns (uint256) {
        // As this function is called by RewardRouter, the parameters are always valid

        address token = _isNative ? IRewardRouterV2(rewardRouter).wnat() : _tokenOut;
        
        uint256 queueIndex = _enqueue(QueueAction({
            actionType: ActionType.UNSTAKE_AND_REDEEM,
            user: _user,
            token: token,
            amount: _olpAmount,
            minOut: _minOut,
            receiver: payable(_receiver),
            isNative: _isNative,
            blockTime: uint40(block.timestamp),
            status: ProcessStatus.ENQUEUED,
            amountOut: 0,
            processBlockTime: 0
        }));

        emit EnqueuedUnstakeAndRedeem(queueIndex, ActionType.UNSTAKE_AND_REDEEM, _user, _tokenOut, _olpAmount, _minOut, _receiver, _isNative);

        return queueIndex;
    }

    function executeQueue(uint256 _endIndex) external override onlyKeeper {
        require(_endIndex < _queue.length, "OlpQueue: index out of bounds");
        require(IRewardRouterV2(rewardRouter).epochStage() == IRewardRouterV2.EpochStage.QUEUE_PROCESSING, "OlpQueue: epoch not in queue processing");

        uint256 startIndex = _getNextProcessIndex();
        require(_endIndex >= startIndex, "OlpQueue: invalid endIndex");

        while (startIndex <= _endIndex) {
            bool shouldContinue = true;

            QueueAction memory action = _queue[startIndex];

            if (action.status == ProcessStatus.ENQUEUED) {
                try this.process(startIndex) returns (bool _wasProcessed) {
                    if (!_wasProcessed) {
                        shouldContinue = false;
                    }
                } catch {
                    try this.cancel(startIndex, CancelMode.BY_KEEPER) returns (bool _wasCancelled) {
                        if (!_wasCancelled) {
                            shouldContinue = false;
                        }
                    } catch {
                        // Compared to PositionManager, there is no Risk Premium here.
                        // Therefore, IncreaseIndex is necessary and Continue does not need to be false.
                        // shouldContinue = false;
                    }
                }
            }

            if (!shouldContinue) { break; }

            _lastProcessedIndex = startIndex;
            startIndex++;
        }
    }

    function process(uint256 _index) public override nonReentrant returns (bool){
        require(msg.sender == address(this), "OlpQueue: Invalid sender");
        require(IRewardRouterV2(rewardRouter).epochStage() == IRewardRouterV2.EpochStage.QUEUE_PROCESSING, "OlpQueue: epoch not in queue processing");

        QueueAction storage action = _queue[_index];
        if (action.status == ProcessStatus.PROCESSED || action.status == ProcessStatus.CANCELLED) { return true; }

        // Get olpManager address once and reuse it
        address olpManagerAddress = IRewardRouterV2(rewardRouter).olpManager();
        
        // Get OLP price: true for MINT_AND_STAKE (maximize, unfavorable for buyer), false for UNSTAKE_AND_REDEEM (minimize, unfavorable for seller)
        bool maximisePrice = action.actionType == ActionType.MINT_AND_STAKE;
        uint256 olpPrice = IOlpManager(olpManagerAddress).getPrice(maximisePrice);

        uint256 amountOut = 0;

        if (action.actionType == ActionType.MINT_AND_STAKE) {
            IERC20(action.token).approve(olpManagerAddress, 0);
            IERC20(action.token).approve(olpManagerAddress, action.amount);
            amountOut = IRewardRouterV2(rewardRouter).processMintAndStakeOlp(action.token, action.amount, action.minOut, action.receiver);
        } else if (action.actionType == ActionType.UNSTAKE_AND_REDEEM) {
            IRewardTracker(rewardTracker).releaseUnstakeForAccount(action.user, action.amount);
            amountOut = IRewardRouterV2(rewardRouter).processUnstakeAndRedeemOlp(action.user, action.token, action.amount, action.minOut, payable(action.receiver), action.isNative);
        }

        action.status = ProcessStatus.PROCESSED;
        action.amountOut = amountOut;
        action.processBlockTime = uint40(block.timestamp);

        emit ProcessedQueueAction(_index, action.actionType, action.user, amountOut, olpPrice);

        return true;
    }

    function cancel(uint256 _index, CancelMode _cancelMode) public override nonReentrant returns (bool) {
        require(_index < _queue.length, "OlpQueue: index out of bounds");

        QueueAction storage action = _queue[_index];
        if (action.status == ProcessStatus.PROCESSED || action.status == ProcessStatus.CANCELLED) { return true; }

        bool shouldCancel = false;        

        if (_cancelMode == CancelMode.BY_USER) {
            require(action.user == msg.sender, "OlpQueue: not owner");
            shouldCancel = IRewardRouterV2(rewardRouter).epochStage() == IRewardRouterV2.EpochStage.REQUEST_SUBMISSION;
        } else if (_cancelMode == CancelMode.BY_KEEPER) {
            require(authority.isKeeper(msg.sender) || msg.sender == address(this), "OlpQueue: not keeper");
            shouldCancel = IRewardRouterV2(rewardRouter).epochStage() == IRewardRouterV2.EpochStage.QUEUE_PROCESSING;
        }

        if (!shouldCancel) { return false; }

        if (action.actionType == ActionType.MINT_AND_STAKE) {
            if (action.isNative) {
                _transferOutNATWithGasLimitFallbackToWnat(action.amount, payable(action.user));
            } else {
                IERC20(action.token).safeTransfer(action.user, action.amount);
            }
        } else if (action.actionType == ActionType.UNSTAKE_AND_REDEEM) {
            IRewardTracker(rewardTracker).releaseUnstakeForAccount(action.user, action.amount);
        }

        action.status = ProcessStatus.CANCELLED;
        action.processBlockTime = uint40(block.timestamp);

        emit CancelledQueueAction(_index, action.actionType, action.user, _cancelMode);

        return true;
    }

    function _enqueue(QueueAction memory _action) internal returns (uint256) {
        _queue.push(_action);
        return _queue.length - 1;
    }

    function _getNextProcessIndex() internal view returns (uint256) {
        if (_lastProcessedIndex == UNINITIALIZED_INDEX) return 0;
        unchecked {
            return _lastProcessedIndex + 1;
        }
    }

    function _transferOutNATWithGasLimitFallbackToWnat(uint256 _amountOut, address payable _receiver) internal {
        IWNAT _wnat = IWNAT(wnat);
        _wnat.withdraw(_amountOut);

        // re-assign natTransferGasLimit since only local variables
        // can be used in assembly calls
        uint256 _natTransferGasLimit = natTransferGasLimit;

        bool success;
        // use an assembly call to avoid loading large data into memory
        // input mem[in…(in+insize)]
        // output area mem[out…(out+outsize))]
        assembly {
            success := call(
                _natTransferGasLimit, // gas limit
                _receiver, // receiver
                _amountOut, // value
                0, // in
                0, // insize
                0, // out
                0 // outsize
            )
        }

        if (success) { return; }

        // if the transfer failed, re-wrap the token and send it to the receiver
        _wnat.deposit{ value: _amountOut }();
        _wnat.transfer(address(_receiver), _amountOut);
    }
}

