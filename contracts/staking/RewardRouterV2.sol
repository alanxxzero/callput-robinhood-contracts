// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../libraries/Address.sol";

import "../tokens/interfaces/IERC20.sol";
import "../tokens/libraries/SafeERC20.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWNAT.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouterV2.sol";
import "./interfaces/IVester.sol";
import "./interfaces/IOlpQueue.sol";

import "../interfaces/IOlpManager.sol";
import "../interfaces/IController.sol";

import "../AuthorityUtil.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../proxy/ReentrancyGuardUpgradeable.sol";

contract RewardRouterV2 is IRewardRouterV2, OwnableUpgradeable, ReentrancyGuardUpgradeable, AuthorityUtil {
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isSetup;

    address public override wnat;
    address public override olp;

    address public override feeOlpTracker;
    address public override olpManager;

    address public override controller;
    address public override olpQueue;
    
    // Epoch management
    EpochStage public override epochStage;
    uint256 public override epochRound;

    bool public inPrivateMode;

    uint256 public natTransferGasLimit;
    
    event SetNatTransferGasLimit(uint256 indexed natTransferGasLimit);
    event StakeOlp(address indexed account, uint256 amount);
    event UnstakeOlp(address indexed account, uint256 amount);
    event EpochUpdated(uint256 indexed epochRound, bool isStarted, uint256 timestamp);
    event SetInPrivateMode(bool inPrivateMode);

    modifier onlyOlpQueue() {
        require(msg.sender == olpQueue, "RewardRouter: only olpQueue");
        _;
    }

    receive() external payable {
        require(msg.sender == wnat, "RewardRouter: invalid sender");
    }    

    function initialize(
        address _wnat,
        address _olp,
        address _feeOlpTracker,
        address _olpManager,
        IOptionsAuthority _authority
    ) external initializer {
        require(
            _wnat != address(0) &&
            _olp != address(0) &&
            _feeOlpTracker != address(0) &&
            _olpManager != address(0),
            "Router: invalid addresses"
        );

        __Ownable_init();
        __ReentrancyGuard_init();
        __AuthorityUtil_init__(_authority);

        wnat = _wnat;
        olp = _olp;

        feeOlpTracker = _feeOlpTracker;
        olpManager = _olpManager;

        epochStage = EpochStage.QUEUE_PROCESSING;
        inPrivateMode = true;

        natTransferGasLimit = 500_000;
    }

    function initSetup(
        address _controller,
        address _olpQueue
    ) external onlyAdmin {
        require(_controller != address(0), "RewardRouter: invalid controller");
        require(_olpQueue != address(0), "RewardRouter: invalid olpQueue");
        require(!isSetup, "RewardRouter: setting already initialized");
        isSetup = true;
        controller = _controller;
        olpQueue = _olpQueue;
    }

    function setInPrivateMode(bool _inPrivateMode) external onlyAdmin {
        inPrivateMode = _inPrivateMode;
        emit SetInPrivateMode(_inPrivateMode);
    }

    function setNatTransferGasLimit(uint256 _natTransferGasLimit) external onlyAdmin {
        natTransferGasLimit = _natTransferGasLimit;
        emit SetNatTransferGasLimit(_natTransferGasLimit);
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

    function startEpoch() external onlyKeeper {
        require(epochStage != EpochStage.REQUEST_SUBMISSION, "RewardRouter: epoch already started");
        epochStage = EpochStage.REQUEST_SUBMISSION;
        epochRound++;
        emit EpochUpdated(epochRound, true, block.timestamp);
    }

    function endEpoch() external onlyKeeper {
        require(epochStage == EpochStage.REQUEST_SUBMISSION, "RewardRouter: epoch not started");
        epochStage = EpochStage.QUEUE_PROCESSING;
        emit EpochUpdated(epochRound, false, block.timestamp);
    }
    
    function mintAndStakeOlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minOlp) external nonReentrant returns (uint256) {
        require(!inPrivateMode, "RewardRouter: action not enabled");
        require(epochStage == EpochStage.QUEUE_PROCESSING, "RewardRouter: epoch not ended");
        require(!IOlpQueue(olpQueue).hasPendingQueue(), "RewardRouter: pending queue");
        return _mintAndStakeOlp(msg.sender, msg.sender, _token, _amount, _minUsdg, _minOlp);
    }

    function mintAndStakeOlpNAT(uint256 _minUsdg, uint256 _minOlp) external payable nonReentrant returns (uint256) {
        require(!inPrivateMode, "RewardRouter: action not enabled");
        require(epochStage == EpochStage.QUEUE_PROCESSING, "RewardRouter: epoch not ended");
        require(!IOlpQueue(olpQueue).hasPendingQueue(), "RewardRouter: pending queue");

        IController(controller).validateNATSupport();
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        // convert NAT to WNAT
        // get approval from Olp Manager
        IWNAT(wnat).deposit{value: msg.value}();
        IERC20(wnat).approve(olpManager, msg.value);

        return _mintAndStakeOlp(address(this), msg.sender, wnat, msg.value, _minUsdg, _minOlp);
    }

    function submitMintAndStakeOlp(
        address _token,
        uint256 _amount,
        uint256 _minOut,
        address payable _receiver,
        bool _isNative
    ) external payable nonReentrant returns (uint256) {
        address _olpQueue = olpQueue;

        _validateSubmission(_token, _amount, _receiver, true);

        if (_isNative) {
            IController(controller).validateNATSupport();
            require(msg.value > 0, "RewardRouter: invalid msg.value");
            require(msg.value == _amount, "RewardRouter: invalid msg.value");
            require(_token == wnat, "RewardRouter: invalid token");

            // convert NAT to WNAT
            // get approval from Olp Manager
            IWNAT(_token).deposit{value: msg.value}();
            IERC20(_token).safeTransfer(_olpQueue, msg.value);
        } else {
            require(msg.value == 0, "RewardRouter: invalid msg.value");
            IERC20(_token).safeTransferFrom(msg.sender, _olpQueue, _amount);
        }

        return IOlpQueue(_olpQueue).enqueueMintAndStake(msg.sender, _token, _amount, _minOut, _receiver, _isNative);
    }

    function processMintAndStakeOlp(address _token, uint256 _amount, uint256 _minOut, address _receiver) external nonReentrant onlyOlpQueue returns (uint256) {
        require(epochStage == EpochStage.QUEUE_PROCESSING, "RewardRouter: epoch not ended");
        return _mintAndStakeOlp(olpQueue, _receiver, _token, _amount, 0, _minOut);
    }

    function unstakeAndRedeemOlp(address _tokenOut, uint256 _olpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(!inPrivateMode, "RewardRouter: action not enabled");
        require(epochStage == EpochStage.QUEUE_PROCESSING, "RewardRouter: epoch not ended");
        require(!IOlpQueue(olpQueue).hasPendingQueue(), "RewardRouter: pending queue");
        return _unstakeAndRedeemOlp(msg.sender, _tokenOut, _olpAmount, _minOut, _receiver);
    }

    function unstakeAndRedeemOlpNAT(uint256 _olpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(!inPrivateMode, "RewardRouter: action not enabled");
        require(epochStage == EpochStage.QUEUE_PROCESSING, "RewardRouter: epoch not ended");
        require(!IOlpQueue(olpQueue).hasPendingQueue(), "RewardRouter: pending queue");
        
        IController(controller).validateNATSupport();
        
        uint256 amountOut = _unstakeAndRedeemOlp(msg.sender, wnat, _olpAmount, _minOut, address(this));

        // convert WNAT to NAT
        // send NAT to receiver
        IWNAT(wnat).withdraw(amountOut);
        _receiver.sendValue(amountOut);

        return amountOut;
    }

    function submitUnstakeAndRedeemOlp(
        address _tokenOut,
        uint256 _olpAmount,
        uint256 _minOut,
        address _receiver,
        bool _isNative
    ) external nonReentrant returns (uint256) {
        _validateSubmission(_tokenOut, _olpAmount, _receiver, false);

        if (_isNative) {
            IController(controller).validateNATSupport();
            require(_tokenOut == wnat, "RewardRouter: invalid token");
        }

        IRewardTracker(feeOlpTracker).reserveUnstakeForAccount(msg.sender, _olpAmount);
        
        return IOlpQueue(olpQueue).enqueueUnstakeAndRedeem(msg.sender, _tokenOut, _olpAmount, _minOut, _receiver, _isNative);
    }

    function processUnstakeAndRedeemOlp(address _account, address _tokenOut, uint256 _olpAmount, uint256 _minOut, address payable _receiver, bool _isNative) external nonReentrant onlyOlpQueue returns (uint256) {
        require(epochStage == EpochStage.QUEUE_PROCESSING, "RewardRouter: epoch not ended");

        if (_isNative) {
            uint256 amountOut = _unstakeAndRedeemOlp(_account, _tokenOut, _olpAmount, 0, address(this));
            _transferOutNATWithGasLimitFallbackToWnat(amountOut, _receiver);
            return amountOut;
        }

        return _unstakeAndRedeemOlp(_account, _tokenOut, _olpAmount, _minOut, _receiver);
    }

    function claim() external nonReentrant {
        address account = msg.sender;
        IRewardTracker(feeOlpTracker).claimForAccount(account, account);
    }

    // to help users withdraw their rewards to NAT (only valid when reward token is wnat)
    function handleRewards(
        bool _shouldClaimReward, // will be always true
        bool _shouldConvertRewardToNAT
    ) external nonReentrant {
        address account = msg.sender;

        if (_shouldClaimReward) {
            if (_shouldConvertRewardToNAT) {
                address rewardToken = IRewardTracker(feeOlpTracker).rewardToken(); // reward token is normally weth
                require(rewardToken == wnat, "RewardRouter: invalid rewardToken");

                uint256 rewardAmount = IRewardTracker(feeOlpTracker).claimForAccount(account, address(this));
                IWNAT(wnat).withdraw(rewardAmount);
                payable(account).sendValue(rewardAmount);
            } else {
                IRewardTracker(feeOlpTracker).claimForAccount(account, account);
            }
        }
    }

    function _mintAndStakeOlp(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minOlp) internal returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        // Send token to Olp Manager and OLP to account
        uint256 olpAmount = IOlpManager(olpManager).addLiquidityForAccount(_fundingAccount, _account, _token, _amount, _minUsdg, _minOlp);
        
        // Stake fOLP and sOLP
        IRewardTracker(feeOlpTracker).stakeForAccount(_account, _account, olp, olpAmount);

        emit StakeOlp(_account, olpAmount);

        return olpAmount;
    }

    function _unstakeAndRedeemOlp(address _account, address _tokenOut, uint256 _olpAmount, uint256 _minOut, address _receiver) internal returns (uint256) {
        require(_olpAmount > 0, "RewardRouter: invalid _olpAmount");

        // unstake sOLP and fOLP in order
        // give olp to Olp Manager and get tokenOut from Olp Manager and send it to receiver
        IRewardTracker(feeOlpTracker).unstakeForAccount(_account, olp, _olpAmount, _account); // transfer unstake amount of OLP to account
        uint256 amountOut = IOlpManager(olpManager).removeLiquidityForAccount(_account, _tokenOut, _olpAmount, _minOut, _receiver);

        emit UnstakeOlp(_account, _olpAmount);

        return amountOut;
    }

    function _validateSubmission(address _token, uint256 _amount, address _receiver, bool _isMintAndStake) private view {
        address _olpManager = olpManager;
        require(epochStage == EpochStage.REQUEST_SUBMISSION, "RewardRouter: epoch not started");
        require(_amount > 0, "RewardRouter: invalid _amount");
        require(_receiver != address(0), "RewardRouter: invalid receiver");
        require(IOlpManager(_olpManager).isEnabledToken(_token), "RewardRouter: _token is not enabled");

        if (!_isMintAndStake) {
            require(IOlpManager(_olpManager).isCooldownPassed(msg.sender), "RewardRouter: cooldown period not passed");
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
