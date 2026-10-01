// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../proxy/OwnableUpgradeable.sol";
import "../proxy/ReentrancyGuardUpgradeable.sol";
import "../tokens/ERC4626Upgradeable.sol";
import "../tokens/libraries/SafeERC20.sol";
import "../staking/interfaces/IRewardRouterV2.sol";
import "../staking/interfaces/IRewardTracker.sol";

contract WOLP is OwnableUpgradeable, ERC4626Upgradeable, ReentrancyGuardUpgradeable {
	using SafeERC20 for IERC20;
	
	IRewardRouterV2 public rewardRouterV2;

	function initialize(
			string memory _name,
			string memory _symbol,
			address _asset, // fOLP
			address _rewardRouterV2
	) public initializer {
			__Ownable_init();
			__ReentrancyGuard_init();
			__ERC4626_init(IERC20(_asset));
			__ERC20_init(_name, _symbol);

			rewardRouterV2 = IRewardRouterV2(_rewardRouterV2);

			_mint(msg.sender, 100);
	}

	// @dev Claims rewards and automatically converts reward tokens to fOLP
	// @dev Process:
	//      1. Claims all pending rewards via handleRewards
	//      2. Converts claimed reward tokens to OLP tokens
	//      3. Stakes converted OLP tokens to receive fOLP
	modifier updateRewards() {
		address rewardToken = IRewardTracker(asset()).rewardToken();
		uint256 rewardTokenBefore = IERC20(rewardToken).balanceOf(address(this));
		
		rewardRouterV2.handleRewards(true, false);

		uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this)) - rewardTokenBefore;

		if (rewardAmount > 0) {
			rewardRouterV2.mintAndStakeOlp(address(rewardToken), rewardAmount, 0, 0);
		}

		_;
	}
	
 	// @dev deposit specified token -> receive corresponding WOLP shares
	function deposit(
		address token, // token used to purchase OLP
		uint256 amount,
		address receiver
	) public nonReentrant updateRewards returns (uint256) {
		require(token != address(0), "WOLP: invalid token address");
		require(amount > 0, "WOLP: invalid amount");
		
		// Buy OLP tokens using specified token
		IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
		address olpManager = rewardRouterV2.olpManager();
		IERC20(token).approve(olpManager, amount);	
		uint256 receivedAmount = rewardRouterV2.mintAndStakeOlp(token, amount, 0, 0);

		// Calculate WOLP shares based on received OLP tokens
		uint256 maxAssets = maxDeposit(receiver);
		if (receivedAmount > maxAssets) {
			revert ERC4626ExceededMaxDeposit(receiver, receivedAmount, maxAssets);
		}
		uint256 shares = previewDeposit(receivedAmount);

		_mint(receiver, shares);

		return shares;
	}
	
	// @dev burn specified WOLP shares -> receive corresponding fOLP tokens
	function redeem(uint256 shares, address receiver, address owner) public override nonReentrant updateRewards returns (uint256) {
		require(shares > 0, "WOLP: invalid shares amount");
		return super.redeem(shares, receiver, owner); 
	}

	// @dev disabled: deposit fOLP -> get WOLP shares
	function deposit(uint256 assets, address receiver) public override updateRewards returns (uint256) {
		revert("WOLP: deposit is not allowed");
		return super.deposit(assets, receiver);
	}

	// @dev disabled: specify WOLP shares -> deposit required fOLP
	function mint(uint256 shares, address receiver) public override nonReentrant updateRewards returns (uint256) {
		revert("WOLP: mint is not allowed");
		return super.mint(shares, receiver);
	}

	// @dev disabled: burn WOLP shares -> withdraw fOLP
	function withdraw(uint256 assets, address receiver, address owner) public override nonReentrant updateRewards returns (uint256) {
		revert("WOLP: withdraw is not allowed");
		return super.withdraw(assets, receiver, owner);
	}
}
