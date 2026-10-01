// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./chains/interfaces/IPrimaryOracle.sol";
import "../proxy/OwnableUpgradeable.sol";
import "../AuthorityUtil.sol";

/// @notice Default placeholder for chains without a primary price oracle.
/// @dev Keep the primary feed disabled until a functional oracle is configured.
contract PrimaryOracle is IPrimaryOracle, OwnableUpgradeable, AuthorityUtil {
    uint256 public constant PRICE_PRECISION = 10 ** 30;

    function initialize(IOptionsAuthority _authority) external initializer {
        __Ownable_init();
        __AuthorityUtil_init__(_authority);
    }

    function getPrice(address _token, bool _maximise) public override view returns (uint256) {
        revert("PrimaryOracle: NOT_IMPLEMENTED");
    }
}
