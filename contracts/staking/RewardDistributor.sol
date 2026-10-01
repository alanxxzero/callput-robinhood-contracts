// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../tokens/interfaces/IERC20.sol";
import "../tokens/libraries/SafeERC20.sol";
import "../libraries/ReentrancyGuard.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardTracker.sol";

import "../proxy/OwnableUpgradeable.sol";
import "../proxy/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IOptionsAuthority.sol";
import "../AuthorityUtil.sol";

contract RewardDistributor is IRewardDistributor, OwnableUpgradeable, ReentrancyGuardUpgradeable, AuthorityUtil {
    using SafeERC20 for IERC20;
    
    address public rewardTracker;

    address public override rewardToken;
    uint256 public override tokensPerInterval;
    uint256 public lastDistributionTime;

    event Distribute(uint256 indexed amount);
    event TokensPerIntervalChange(uint256 indexed amount);

    function initialize(
        address _rewardToken,
        address _rewardTracker,
        IOptionsAuthority _authority
    ) external initializer {
        require(_rewardToken != address(0) && _rewardTracker != address(0), "RewardDistributor: invalid addresses");

        __Ownable_init();
        __ReentrancyGuard_init();
        __AuthorityUtil_init__(_authority);
        
        rewardToken = _rewardToken;
        rewardTracker = _rewardTracker;
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

    // emergency only
    function updateLastDistributionTime() external onlyAdmin {
        lastDistributionTime = block.timestamp;
    }

    function setTokensPerInterval(uint256 _amount) external onlyFeeDistributor {
        require(lastDistributionTime != 0, "RewardDistributor: invalid lastDistributionTime");
        IRewardTracker(rewardTracker).updateRewards();
        tokensPerInterval = _amount;
        emit TokensPerIntervalChange(_amount);
    }

    function pendingRewards() public view override returns (uint256) {
        if (block.timestamp == lastDistributionTime) {
            return 0;
        }

        uint256 timeDiff = block.timestamp - lastDistributionTime;
        
        return (tokensPerInterval * timeDiff);
    }

    function distribute() external override returns (uint256) {
        require(msg.sender == rewardTracker, "RewardDistributor: invalid msg.sender");

        uint256 amount = pendingRewards();
        if (amount == 0) { return 0; }

        lastDistributionTime = block.timestamp;
        
        // if amount is greater than balance, set amount to balance
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        if (amount > balance) { amount = balance; }

        IERC20(rewardToken).safeTransfer(msg.sender, amount);

        emit Distribute(amount);

        return amount;
    }
}
