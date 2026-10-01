// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../tokens/interfaces/IERC20.sol";

/**
 * @title PublicFaucet
 * @dev Testnet-only public faucet: any wallet can claim a fixed amount of the
 * configured (mock) token once per cooldown window, as a direct user tx.
 *
 * Dispenses from this contract's own pre-funded balance — it holds NO mint
 * authority on the token (the mock USDC's mint is constructor-locked to the
 * deployer, so funding happens by minting/transferring TO this contract).
 *
 * Deliberately minimal and non-upgradeable (plain deploy): claim() with a
 * per-address cooldown, plus owner-only knobs for amount/cooldown and a
 * recovery escape hatch.
 */
contract PublicFaucet {
    IERC20 public immutable token;
    address public owner;

    uint256 public dispenseAmount;
    uint256 public cooldown;

    mapping(address => uint256) public lastClaimAt;

    event Claimed(address indexed account, uint256 amount);
    event DispenseAmountUpdated(uint256 amount);
    event CooldownUpdated(uint256 cooldown);

    modifier onlyOwner() {
        require(msg.sender == owner, "PublicFaucet: not owner");
        _;
    }

    constructor(IERC20 _token, uint256 _dispenseAmount, uint256 _cooldown) {
        require(address(_token) != address(0), "PublicFaucet: invalid token");
        token = _token;
        owner = msg.sender;
        dispenseAmount = _dispenseAmount;
        cooldown = _cooldown;
    }

    /// @dev Claim `dispenseAmount` tokens; one claim per `cooldown` per wallet.
    function claim() external {
        uint256 last = lastClaimAt[msg.sender];
        require(
            last == 0 || block.timestamp - last >= cooldown,
            "PublicFaucet: cooldown not elapsed"
        );
        uint256 amount = dispenseAmount;
        require(
            token.balanceOf(address(this)) >= amount,
            "PublicFaucet: faucet empty"
        );

        lastClaimAt[msg.sender] = block.timestamp;
        require(token.transfer(msg.sender, amount), "PublicFaucet: transfer failed");

        emit Claimed(msg.sender, amount);
    }

    function setDispenseAmount(uint256 _amount) external onlyOwner {
        dispenseAmount = _amount;
        emit DispenseAmountUpdated(_amount);
    }

    function setCooldown(uint256 _cooldown) external onlyOwner {
        cooldown = _cooldown;
        emit CooldownUpdated(_cooldown);
    }

    /// @dev Recover remaining tokens (e.g. decommissioning the faucet).
    function recover(address _receiver, uint256 _amount) external onlyOwner {
        require(token.transfer(_receiver, _amount), "PublicFaucet: transfer failed");
    }
}
