
// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../tokens/interfaces/IERC20.sol";
import "../tokens/libraries/SafeERC20.sol";
import "../interfaces/IVault.sol";
import "../AuthorityUtil.sol";
import "../staking/interfaces/IRewardDistributor.sol";

import "../proxy/OwnableUpgradeable.sol";

// For testnet only
contract Faucet is OwnableUpgradeable, AuthorityUtil {

    mapping(address => uint256) public lastDistributed;
    mapping(bytes => uint256) public lastDistributed_byUserIdHash;

    uint256 distributionPeriod;

    function initialize(
      IOptionsAuthority _authority
    ) external initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);

        distributionPeriod = 7 days;
    }

    receive() external payable {}

    function isDistributionAvailable(bytes memory userIdHash, address receiver) public view returns (bool) {
        uint256 timeElapsed = block.timestamp - lastDistributed[receiver];
        uint256 timeElapsed_byUserIdHash = block.timestamp - lastDistributed_byUserIdHash[userIdHash];

        return lastDistributed[receiver] == 0 
          || (timeElapsed >= distributionPeriod && timeElapsed_byUserIdHash >= distributionPeriod);
    }

    function setDistributionPeriod(uint256 _distributionPeriod) public onlyKeeper {
        distributionPeriod = _distributionPeriod;
    }

    function distribute(
      address[] memory tokens,
      uint256[] memory amounts,
      address[] memory receivers,
      bytes[] memory userIdHashes,
      bool forceDistribute
    ) external onlyKeeper {
        for (uint256 i = 0; i < receivers.length; i++) {
          address receiver = receivers[i]; 
          bytes memory userIdHash = userIdHashes[i];
          if (!isDistributionAvailable(userIdHash, receiver) && !forceDistribute) continue;

          for (uint256 j = 0; j < tokens.length; j++) {
            address token = tokens[j];
            uint256 amount = amounts[j];

            if (token == address(0)) {
              // pure ETH
              payable(receiver).transfer(amount);
            } else {
              // ERC20
              IERC20(token).transfer(receiver, amount);
            }
          }

          lastDistributed[receiver] = block.timestamp;
          lastDistributed_byUserIdHash[userIdHash] = block.timestamp;
        }
    }

    function recoverToken(address tokenAddress, address receiver, uint256 amount) public onlyKeeper {
        if (tokenAddress == address(0)) {
          // send ETH
          payable(receiver).transfer(amount);
        } else {
          // send ERC20
          IERC20(tokenAddress).transfer(receiver, amount);
        }
    }
}