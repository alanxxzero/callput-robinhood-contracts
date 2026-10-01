
// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../tokens/interfaces/IERC20.sol";
import "../tokens/libraries/SafeERC20.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IController.sol";
import "../AuthorityUtil.sol";
import "../staking/interfaces/IRewardDistributor.sol";

import "../proxy/OwnableUpgradeable.sol";

contract FeeDistributor is OwnableUpgradeable, AuthorityUtil {
    using SafeERC20 for IERC20;

    // tokens
    address public rewardToken;
    
    // other contracts
    address public controller;
    address public sRewardDistributor;
    address public mRewardDistributor;
    address public lRewardDistributor;

    // addresses
    address public treasury;
    address public governance;

    // rates
    uint256 public treasuryRate;
    uint256 public governanceRate;
    uint256 public olpRewardRate;

    uint256 public distributionPeriod;
    uint256 public lastFeeDistribution; // timestamp
    uint256 public lastOlpRewardsDistribution; // timesstamp

    // pending olp rewards (solp, molp, lolp)
    mapping(address => uint256) public pendingOLPRewards;

    event FeeDistribution(address indexed receiver, uint256 amount);
    event SetRewardToken(address indexed rewardToken);
    event SetTreasury(address indexed treasury);
    event SetGovernance(address indexed governance);
    event SetRate(uint256 indexed treasuryRate, uint256 indexed governanceRate, uint256 indexed olpRewardRate);
    event SetDistributionPeriod(uint256 indexed period);
    event SetRewardDistributor(address indexed sRewardDistributor, address indexed mRewardDistributor, address indexed lRewardDistributor);

    function initialize(
        address _rewardToken,
        address _treasury,
        address _governance,
        address _controller,
        address _sRewardDistributor,
        address _mRewardDistributor,
        address _lRewardDistributor,
        IOptionsAuthority _authority
    ) external initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        require(
          _rewardToken != address(0) &&
          _treasury != address(0) &&
          _governance != address(0) &&
          _controller != address(0) &&
          _sRewardDistributor != address(0) &&
          _mRewardDistributor != address(0) &&
          _lRewardDistributor != address(0),
          "FeeDistributor: invalid address (zero address)"
        );

        rewardToken = _rewardToken;
        treasury = _treasury;
        governance = _governance;
       
        controller = _controller;

        sRewardDistributor = _sRewardDistributor;
        mRewardDistributor = _mRewardDistributor;
        lRewardDistributor = _lRewardDistributor;

        distributionPeriod = 7 days;
    }

    // distribute fee to treasury (address), governance (address), and pending olp rewards pool
    function distributeFee(address[] memory _tokens) external onlyKeeper {
        address[3] memory vaults = IController(controller).getVaults();

        uint256 sVaultOutcome;
        uint256 mVaultOutcome;
        uint256 lVaultOutcome;

        uint256 rewardTotalBefore = IERC20(rewardToken).balanceOf(address(this));

        for (uint256 i = 0; i < _tokens.length;) {
          address[] memory _path = new address[](2);
          _path[0] = _tokens[i];
          _path[1] = rewardToken;

          uint256 feeFromSVault = IVault(vaults[0]).withdrawFees(_tokens[i], address(this));
          uint256 feeFromMVault = IVault(vaults[1]).withdrawFees(_tokens[i], address(this));
          uint256 feeFromLVault = IVault(vaults[2]).withdrawFees(_tokens[i], address(this));

          // convert feeTokenAmountTotal to rewardToken
          if (_tokens[i] == rewardToken) {
            sVaultOutcome += feeFromSVault;
            mVaultOutcome += feeFromMVault;
            lVaultOutcome += feeFromLVault;
          } else {
            _approve(_tokens[i], controller);
            sVaultOutcome += _swap(vaults[0], _path, feeFromSVault);
            mVaultOutcome += _swap(vaults[1], _path, feeFromMVault);
            lVaultOutcome += _swap(vaults[2], _path, feeFromLVault);
          }

          unchecked { i++; }
        }

        uint256 rewardTotal = IERC20(rewardToken).balanceOf(address(this)) - rewardTotalBefore;

        uint256 treasuryAmount = 0;
        uint256 governanceAmount = 0;
        uint256 olpReward = 0;

        // Treasury (only distribute if treasuryRate > 0)
        if (treasuryRate > 0) {
            treasuryAmount = rewardTotal * treasuryRate / 100;
            if (treasuryAmount > 0) {
                IERC20(rewardToken).safeTransfer(treasury, treasuryAmount);
                emit FeeDistribution(treasury, treasuryAmount);
            }
        }

        // Governance (only distribute if governanceRate > 0)
        if (governanceRate > 0) {
            governanceAmount = rewardTotal * governanceRate / 100;
            if (governanceAmount > 0) {
                IERC20(rewardToken).safeTransfer(governance, governanceAmount);
                emit FeeDistribution(governance, governanceAmount);
            }
        }

        // OLP Reward Pool (only distribute if olpRewardRate > 0 and there are active vaults)
        if (olpRewardRate > 0) {
            olpReward = rewardTotal * olpRewardRate / 100;
            uint256 vaultOutcomeTotal = sVaultOutcome + mVaultOutcome + lVaultOutcome;

            if (vaultOutcomeTotal > 0 && olpReward > 0) {
                uint256 solpReward = 0;
                uint256 molpReward = 0;
                uint256 lolpReward = 0;

                // Calculate rewards only for active vaults (outcome > 0)
                if (sVaultOutcome > 0) {
                    solpReward = olpReward * sVaultOutcome / vaultOutcomeTotal;
                    pendingOLPRewards[sRewardDistributor] += solpReward;
                    emit FeeDistribution(sRewardDistributor, solpReward);
                }

                if (mVaultOutcome > 0) {
                    molpReward = olpReward * mVaultOutcome / vaultOutcomeTotal;
                    pendingOLPRewards[mRewardDistributor] += molpReward;
                    emit FeeDistribution(mRewardDistributor, molpReward);
                }

                if (lVaultOutcome > 0) {
                    lolpReward = olpReward * lVaultOutcome / vaultOutcomeTotal;
                    pendingOLPRewards[lRewardDistributor] += lolpReward;
                    emit FeeDistribution(lRewardDistributor, lolpReward);
                }

                // Handle remaining due to rounding: distribute to the vault with the largest outcome
                uint256 distributed = solpReward + molpReward + lolpReward;
                if (distributed < olpReward) {
                    uint256 remaining = olpReward - distributed;
                    
                    // Find the vault with the largest outcome
                    if (sVaultOutcome >= mVaultOutcome && sVaultOutcome >= lVaultOutcome && sVaultOutcome > 0) {
                        pendingOLPRewards[sRewardDistributor] += remaining;
                        emit FeeDistribution(sRewardDistributor, remaining);
                    } else if (mVaultOutcome >= lVaultOutcome && mVaultOutcome > 0) {
                        pendingOLPRewards[mRewardDistributor] += remaining;
                        emit FeeDistribution(mRewardDistributor, remaining);
                    } else if (lVaultOutcome > 0) {
                        pendingOLPRewards[lRewardDistributor] += remaining;
                        emit FeeDistribution(lRewardDistributor, remaining);
                    }
                }
            }
        }

        // Handle any remaining tokens due to rounding errors
        // Send remaining to treasury
        uint256 totalDistributed = treasuryAmount + governanceAmount + olpReward;
        if (totalDistributed < rewardTotal) {
            uint256 remaining = rewardTotal - totalDistributed;
            IERC20(rewardToken).safeTransfer(treasury, remaining);
            emit FeeDistribution(treasury, remaining);
        }

        lastFeeDistribution = block.timestamp;
    }

    // distribute pending olp rewards to reward distributors
    function distributeOLPRewards() external onlyKeeper {
        require(block.timestamp - lastOlpRewardsDistribution >= distributionPeriod, "FeeDistributor: not ready");
        
        uint256 sAmount = (pendingOLPRewards[sRewardDistributor] / distributionPeriod) * distributionPeriod;
        uint256 mAmount = (pendingOLPRewards[mRewardDistributor] / distributionPeriod) * distributionPeriod;
        uint256 lAmount = (pendingOLPRewards[lRewardDistributor] / distributionPeriod) * distributionPeriod;

        if (sAmount > 0) {
            IERC20(rewardToken).safeTransfer(sRewardDistributor, sAmount);
            IRewardDistributor(sRewardDistributor).setTokensPerInterval(sAmount / distributionPeriod);
        }

        if (mAmount > 0) {
            IERC20(rewardToken).safeTransfer(mRewardDistributor, mAmount);
            IRewardDistributor(mRewardDistributor).setTokensPerInterval(mAmount / distributionPeriod);
        }

        if (lAmount > 0) {
            IERC20(rewardToken).safeTransfer(lRewardDistributor, lAmount);
            IRewardDistributor(lRewardDistributor).setTokensPerInterval(lAmount / distributionPeriod);
        }

        // Updating the pending rewards after distribution
        pendingOLPRewards[sRewardDistributor] -= sAmount;
        pendingOLPRewards[mRewardDistributor] -= mAmount;
        pendingOLPRewards[lRewardDistributor] -= lAmount;

        lastOlpRewardsDistribution = block.timestamp;
    }

    function setRewardToken(address _rewardToken) public onlyAdmin {
        require(_rewardToken != address(0), "FeeDistributor: invalid address (zero address)");
        rewardToken = _rewardToken;
        emit SetRewardToken(_rewardToken);
    }

    function setTreasury(address _treasury) public onlyAdmin {
        require(_treasury != address(0), "FeeDistributor: invalid address (zero address)");
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }
    
    function setGovernance(address _governance) public onlyAdmin {
        require(_governance != address(0), "FeeDistributor: invalid address (zero address)");
        governance = _governance;
        emit SetGovernance(_governance);
    }

    function setRate(uint256 _treasuryRate, uint256 _governanceRate, uint256 _olpRewardRate) public onlyAdmin {
        require(_treasuryRate + _olpRewardRate + _governanceRate == 100, "FeeDistributor: invalid rate");
        treasuryRate = _treasuryRate;
        governanceRate = _governanceRate;
        olpRewardRate = _olpRewardRate;

        emit SetRate(_treasuryRate, _governanceRate, _olpRewardRate);
    }

    function setDistributionPeriod(uint256 _distributionPeriod, bool _force) public onlyAdmin {
        if (!_force) {
          require(_distributionPeriod >= 1 days, "FeeDistributor: invalid period");
        }
        distributionPeriod = _distributionPeriod;

        emit SetDistributionPeriod(_distributionPeriod);
    }

    function setRewardDistributor(address _sRewardDistributor, address _mRewardDistributor, address _lRewardDistributor) public onlyAdmin {
      require(
        _sRewardDistributor != address(0) &&
        _mRewardDistributor != address(0) &&
        _lRewardDistributor != address(0),
        "FeeDistributor: invalid address (zero address)"
      );
      
      sRewardDistributor = _sRewardDistributor;
      mRewardDistributor = _mRewardDistributor;
      lRewardDistributor = _lRewardDistributor;
      
      emit SetRewardDistributor(_sRewardDistributor, _mRewardDistributor, _lRewardDistributor);
    }

    function _approve(address token, address spender) private {
      // check allowance
      uint256 allowance = IERC20(token).allowance(address(this), spender);

      if (allowance == 0) {
        IERC20(token).approve(spender, type(uint256).max);
      }
    }

    function _swap(address _vault, address[] memory _path, uint256 _fee) private returns (uint256) {
      if (_fee > 0) {
        return IController(controller).swap(_vault, _path, _fee, 0, address(this));
      }

      return 0;
    }
}