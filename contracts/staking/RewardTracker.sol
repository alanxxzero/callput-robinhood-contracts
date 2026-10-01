// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../tokens/interfaces/IERC20.sol";
import "../tokens/libraries/SafeERC20.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardTracker.sol";

import "../interfaces/IOlpManager.sol";

import "../AuthorityUtil.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../proxy/ReentrancyGuardUpgradeable.sol";

contract RewardTracker is IERC20, OwnableUpgradeable, ReentrancyGuardUpgradeable, IRewardTracker, AuthorityUtil {
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant PRECISION = 1e30;

    uint8 public constant decimals = 18;

    bool public isSetup;

    string public name;
    string public symbol;

    address public distributor;
    mapping (address => bool) public isDepositToken;
    mapping (address => mapping (address => uint256)) public override depositBalances;
    mapping (address => uint256) public totalDepositSupply;

    uint256 public override totalSupply;
    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowances;
    mapping (address => uint256) public reservedUnstakeAmounts;

    uint256 public cumulativeRewardPerToken;
    mapping (address => uint256) public override stakedAmounts;
    mapping (address => uint256) public claimableReward;
    mapping (address => uint256) public previousCumulatedRewardPerToken;
    mapping (address => uint256) public override cumulativeRewards;
    mapping (address => uint256) public override averageStakedAmounts;

    bool public inPrivateTransferMode;
    bool public inPrivateStakingMode;
    bool public inPrivateClaimingMode;
    
    mapping (address => bool) public isHandler; // handler: RewardRouterV2

    event Claim(address indexed receiver, uint256 amount);
    event SetInPrivateClaimingMode(bool inPrivateClaimingMode);
    event SetHandler(address indexed handler, bool isActive);
    event SetAuthorizedForTransfer(address indexed partner, bool isAuthorized);
    event SetOlpManager(address olpManager);
    event ReserveUnstakeForAccount(address indexed account, uint256 amount);
    event ReleaseUnstakeForAccount(address indexed account, uint256 amount);

    address public depositToken;
    
    address public olpManager; // added at 2024-12-20 for wolp
    mapping (address => bool) public isAuthorizedForTransfer; // for partners only. added at 2024-12-20 for wolp

    function initialize(
        string memory _name,
        string memory _symbol,
        IOptionsAuthority _authority
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __AuthorityUtil_init__(_authority);
        
        name = _name;
        symbol = _symbol;
    }

    function initSetup(
        address _depositToken,
        address _distributor
    ) external onlyAdmin {
        require(_depositToken != address(0), "RewardTracker: invalid deposit token");
        require(_distributor != address(0), "RewardTracker: invalid address");
        require(!isSetup, "RewardTracker: setting already initialized");
        isSetup = true;
        depositToken = _depositToken;
        distributor = _distributor;
    }

    function setInPrivateClaimingMode(bool _inPrivateClaimingMode) external onlyAdmin {
        inPrivateClaimingMode = _inPrivateClaimingMode;
        emit SetInPrivateClaimingMode(_inPrivateClaimingMode);
    }

    function setHandler(address _handler, bool _isActive) external onlyAdmin {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    function setAuthorizedForTransfer(address _partner, bool _isAuthorized) external onlyAdmin {
        isAuthorizedForTransfer[_partner] = _isAuthorized;
        emit SetAuthorizedForTransfer(_partner, _isAuthorized);
    }

    function setOlpManager(address _olpManager) external onlyAdmin {
        olpManager = _olpManager;
        emit SetOlpManager(_olpManager);
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

    // balance of fOLP
    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        if (isAuthorizedForTransfer[msg.sender]) {
            _authorizedTransfer(msg.sender, _recipient, _amount);
            return true;
        }

        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external override returns (bool) {
        // @desc if it is the handler such as RewardRouterV2, it doesn't need to check allowance
        if (isHandler[msg.sender]) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }

        uint256 currentAllowance = allowances[_sender][msg.sender];
        require(currentAllowance >= _amount, "RewardTracker: transfer amount exceeds allowance");

        uint256 nextAllowance;
        unchecked {
            nextAllowance = currentAllowance - _amount;
        }

        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint256 _amount) external override nonReentrant {
        _validateHandler(); // check whether msg.sender is handler
        _stake(_fundingAccount, _account, _depositToken, _amount);
    }

    function reserveUnstakeForAccount(address _account, uint256 _amount) external override nonReentrant {
        _validateHandler();
        require(balances[_account] >= _amount, "RewardTracker: unstake amount exceeds balance");
        unchecked {
            balances[_account] = balances[_account] - _amount;
        }
        reservedUnstakeAmounts[_account] = reservedUnstakeAmounts[_account] + _amount;

        emit ReserveUnstakeForAccount(_account, _amount);
    }

    function releaseUnstakeForAccount(address _account, uint256 _amount) external override nonReentrant {
        _validateHandler();
        require(reservedUnstakeAmounts[_account] >= _amount, "RewardTracker: release amount exceeds reserved");
        unchecked {
            reservedUnstakeAmounts[_account] = reservedUnstakeAmounts[_account] - _amount;
        }
        balances[_account] = balances[_account] + _amount;

        emit ReleaseUnstakeForAccount(_account, _amount);
    }

    function unstakeForAccount(address _account, address _depositToken, uint256 _amount, address _receiver) external override nonReentrant {
        _validateHandler();
        _unstake(_account, _depositToken, _amount, _receiver);
    }

    function tokensPerInterval() external override view returns (uint256) {
        return IRewardDistributor(distributor).tokensPerInterval();
    }

    function updateRewards() external override nonReentrant {
        _updateRewards(address(0));
    }

    function claim(address _receiver) external override nonReentrant returns (uint256) {
        require(!inPrivateClaimingMode, "RewardTracker: action not enabled");
        return _claim(msg.sender, _receiver);
    }

    function claimForAccount(address _account, address _receiver) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    function claimable(address _account) public override view returns (uint256) {
        uint256 stakedAmount = stakedAmounts[_account];
        if (stakedAmount == 0) {
            return claimableReward[_account];
        }
        uint256 supply = totalSupply;
        uint256 pendingRewards = IRewardDistributor(distributor).pendingRewards() * PRECISION;
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken + (pendingRewards / supply);
        return (claimableReward[_account] + (stakedAmount * (nextCumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION));
    }

    function rewardToken() public override view returns (address) {
        return IRewardDistributor(distributor).rewardToken(); // WETH
    }

    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            IERC20(rewardToken()).safeTransfer(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount);
        }

        return tokenAmount;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: mint to the zero address");

        totalSupply = totalSupply + _amount;
        balances[_account] = balances[_account] + _amount;

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: burn from the zero address");

        require(balances[_account] >= _amount, "RewardTracker: burn amount exceeds balance");
        unchecked {
            balances[_account] = balances[_account] - _amount;
        }
        totalSupply = totalSupply - _amount;

        emit Transfer(_account, address(0), _amount);
    }
    
    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "RewardTracker: transfer from the zero address");
        require(_recipient != address(0), "RewardTracker: transfer to the zero address");
        
        _validateHandler();

        require(balances[_sender] >= _amount, "RewardTracker: transfer amount exceeds balance");
        unchecked {
            balances[_sender] = balances[_sender] - _amount;
        }
        balances[_recipient] = balances[_recipient] + _amount;

        emit Transfer(_sender, _recipient,_amount);
    }

    function _authorizedTransfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "RewardTracker: transfer from the zero address");
        require(_recipient != address(0), "RewardTracker: transfer to the zero address");
        
        _validateTransfer();

        _updateRewards(_sender);
        _updateRewards(_recipient);

        require(balances[_sender] >= _amount, "RewardTracker: transfer amount exceeds balance");
        require(stakedAmounts[_sender] >= _amount, "RewardTracker: staked amount exceeds balance");
        require(depositBalances[_sender][depositToken] >= _amount, "RewardTracker: deposit balance exceeds balance");

        unchecked {
            balances[_sender] = balances[_sender] - _amount;
            stakedAmounts[_sender] = stakedAmounts[_sender] - _amount;
            depositBalances[_sender][depositToken] -= _amount;
        }

        balances[_recipient] = balances[_recipient] + _amount;
        stakedAmounts[_recipient] = stakedAmounts[_recipient] + _amount;
        depositBalances[_recipient][depositToken] += _amount;

        uint256 senderLastAddedAt = IOlpManager(olpManager).lastAddedAt(_sender);
        IOlpManager(olpManager).setLastAddedAt(_recipient, senderLastAddedAt);
        
        emit Transfer(_sender, _recipient,_amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "RewardTracker: approve from the zero address");
        require(_spender != address(0), "RewardTracker: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "RewardTracker: forbidden");
    }

    function _validateTransfer() private view {
        require(isAuthorizedForTransfer[msg.sender], "RewardTracker: forbidden");
    }

    function _stake(address _fundingAccount, address _account, address _depositToken, uint256 _amount) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(depositToken == _depositToken, "RewardTracker: invalid _depositToken");

        // send deposit token to RewardTracker
        IERC20(_depositToken).safeTransferFrom(_fundingAccount, address(this), _amount);

        // update rewards for the account
        _updateRewards(_account);

        // increase staked amounts
        // - increase deposit balances of the account
        // - increase total deposit supply
        stakedAmounts[_account] = stakedAmounts[_account] + _amount;
        depositBalances[_account][_depositToken] += _amount;
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken] + _amount;

        _mint(_account, _amount);
    }

    function _unstake(address _account, address _depositToken, uint256 _amount, address _receiver) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(depositToken == _depositToken, "RewardTracker: invalid _depositToken");

        _updateRewards(_account);

        uint256 stakedAmount = stakedAmounts[_account];
        require(stakedAmounts[_account] >= _amount, "RewardTracker: _amount exceeds stakedAmount");
        unchecked {
            stakedAmounts[_account] = stakedAmount - _amount;
        }

        uint256 depositBalance = depositBalances[_account][_depositToken];
        require(depositBalance >= _amount, "RewardTracker: _amount exceeds depositBalance");
        unchecked {
            depositBalances[_account][_depositToken] -= _amount;
        }
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken] - _amount;

        _burn(_account, _amount);
        IERC20(_depositToken).safeTransfer(_receiver, _amount);
    }

    function _updateRewards(address _account) private {
        // get block reward from Reward Distributor
        uint256 blockReward = IRewardDistributor(distributor).distribute();

        // if totalSupply and blockReward are both greater than zero, update cumulative reward per token
        uint256 supply = totalSupply;
        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;

        if (supply > 0 && blockReward > 0) {
            _cumulativeRewardPerToken = _cumulativeRewardPerToken + ((blockReward * PRECISION) / supply);
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        if (_account != address(0)) {
            // update claimable reward and previous cumulative reward per token
            uint256 stakedAmount = stakedAmounts[_account];
            uint256 accountReward = (stakedAmount * (_cumulativeRewardPerToken - previousCumulatedRewardPerToken[_account])) / PRECISION;
            uint256 _claimableReward = claimableReward[_account] + accountReward;
            
            claimableReward[_account] = _claimableReward;
            previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;

            // update average staked amounts and cumulative rewards
            if (_claimableReward > 0 && stakedAmounts[_account] > 0) {
                uint256 nextCumulativeReward = cumulativeRewards[_account] + accountReward;
                
                averageStakedAmounts[_account] = (averageStakedAmounts[_account] * cumulativeRewards[_account] / nextCumulativeReward) + ((stakedAmount * accountReward) / nextCumulativeReward);

                cumulativeRewards[_account] = nextCumulativeReward;
            }
        }
    }
}
