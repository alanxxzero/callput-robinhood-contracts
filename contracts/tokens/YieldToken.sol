// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";

import "./interfaces/IYieldTracker.sol";
import "./interfaces/IYieldToken.sol";

import "../AuthorityUtil.sol";
import "../proxy/Initializable.sol";

contract YieldToken is IERC20, IYieldToken, Initializable, AuthorityUtil {
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    uint256 public nonStakingSupply;

    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) public allowances;

    address[] public yieldTrackers;
    mapping (address => bool) public nonStakingAccounts;

    bool public inWhitelistMode;
    mapping (address => bool) public whitelistedHandlers;

    event SetInfo(string indexed name, string indexed symbol);
    event SetYieldTrackers(address[] indexed yieldTrackers);
    event SetInWhitelistMode(bool indexed inWhitelistMode);
    event SetWhitelistedHandler(address indexed handler, bool isWhitelisted);
    event UpdateNonStakingAccount(address indexed account, bool isNonStakingAccount);

    function __YieldToken_init__(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        IOptionsAuthority _authority
    ) public initializer {
        __AuthorityUtil_init__(_authority);

        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _initialSupply);
    }

    function setInfo(string memory _name, string memory _symbol) external onlyAdmin {
        name = _name;
        symbol = _symbol;
        emit SetInfo(_name, _symbol);
    }

    function setYieldTrackers(address[] memory _yieldTrackers) external onlyAdmin {
        yieldTrackers = _yieldTrackers;
        emit SetYieldTrackers(_yieldTrackers);
    }

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

    function setInWhitelistMode(bool _inWhitelistMode) external onlyAdmin {
        inWhitelistMode = _inWhitelistMode;
        emit SetInWhitelistMode(_inWhitelistMode);
    }

    function setWhitelistedHandler(address _handler, bool _isWhitelisted) external onlyAdmin {
        whitelistedHandlers[_handler] = _isWhitelisted;
        emit SetWhitelistedHandler(_handler, _isWhitelisted);
    }

    function addNonStakingAccount(address _account) external onlyAdmin {
        require(!nonStakingAccounts[_account], "YieldToken: _account already marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = true;
        nonStakingSupply = nonStakingSupply + balances[_account];
        emit UpdateNonStakingAccount(_account, true);
    }

    function removeNonStakingAccount(address _account) external onlyAdmin {
        require(nonStakingAccounts[_account], "YieldToken: _account not marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = false;
        nonStakingSupply = nonStakingSupply - balances[_account];
        emit UpdateNonStakingAccount(_account, false);
    }

    function recoverClaim(address _account, address _receiver) external onlyAdmin {
        for (uint256 i = 0; i < yieldTrackers.length;) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(_account, _receiver);
            unchecked { i++; }
        }
    }

    function claim(address _receiver) external {
        for (uint256 i = 0; i < yieldTrackers.length;) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(msg.sender, _receiver);
            unchecked { i++; }
        }
    }

    function totalStaked() external view override returns (uint256) {
        return totalSupply - nonStakingSupply;
    }

    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    function stakedBalance(address _account) external view override returns (uint256) {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balances[_account];
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external override returns (bool) {
        uint256 currentAllowance = allowances[_sender][msg.sender];
        require(currentAllowance >= _amount, "YieldToken: transfer amount exceeds allowance");

        uint256 nextAllowance;
        unchecked {
            nextAllowance = currentAllowance - _amount;
        }

        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "YieldToken: mint to the zero address");

        _updateRewards(_account);

        totalSupply = totalSupply + _amount;
        balances[_account] = balances[_account] + _amount;

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply + _amount;
        }

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "YieldToken: burn from the zero address");

        _updateRewards(_account);

        require(balances[_account] >= _amount, "YieldToken: burn amount exceeds balance");
        unchecked {
            balances[_account] = balances[_account] - _amount;
        }
        totalSupply = totalSupply - _amount;

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply - _amount;
        }

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "YieldToken: transfer from the zero address");
        require(_recipient != address(0), "YieldToken: transfer to the zero address");

        if (inWhitelistMode) {
            require(whitelistedHandlers[msg.sender], "YieldToken: msg.sender not whitelisted");
        }

        _updateRewards(_sender);
        _updateRewards(_recipient);

        require(balances[_sender] >= _amount, "YieldToken: transfer amount exceeds balance");
        unchecked {
            balances[_sender] = balances[_sender] - _amount;
        }
        balances[_recipient] = balances[_recipient] + _amount;

        if (nonStakingAccounts[_sender]) {
            nonStakingSupply = nonStakingSupply - _amount;
        }
        if (nonStakingAccounts[_recipient]) {
            nonStakingSupply = nonStakingSupply + _amount;
        }

        emit Transfer(_sender, _recipient,_amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "YieldToken: approve from the zero address");
        require(_spender != address(0), "YieldToken: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _updateRewards(address _account) private {
        for (uint256 i = 0; i < yieldTrackers.length;) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).updateRewards(_account);
            unchecked { i++; }
        }
    }
}