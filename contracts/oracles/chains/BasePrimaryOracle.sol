// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IBasePrimaryOracle.sol";
import "./interfaces/IPrimaryOracle.sol";
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IChainlinkFlags.sol";

import "../../proxy/OwnableUpgradeable.sol";
import "../../AuthorityUtil.sol";

contract BasePrimaryOracle is IPrimaryOracle, IBasePrimaryOracle, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    function initialize(IOptionsAuthority _authority) external initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);
    }

    function getPrice(address _token, bool _maximise) public override view returns (uint256) {
        revert ("BasePrimaryOracle: NOT_IMPLEMENTED");
    }
}
