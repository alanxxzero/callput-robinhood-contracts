// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IOptionsAuthority.sol";
import "./proxy/Initializable.sol";

abstract contract AuthorityUtil is Initializable {
  IOptionsAuthority public authority;

  event AuthorityUpdated(IOptionsAuthority indexed authority);

  function __AuthorityUtil_init__(IOptionsAuthority _authority) public initializer {
    require(address(_authority) != address(0), "AuthorityUtils: invalid authority address (zero address)");

    authority = _authority;
    emit AuthorityUpdated(_authority);
  }

  modifier onlyAdmin() {
    require(authority.isAdmin(msg.sender), "AuthorityUtils: only admin");
    _;
  }

  modifier onlyKeeper() {
    require(authority.isKeeper(msg.sender), "AuthorityUtils: only keeper");
    _;
  }
  
  modifier onlyPositionKeeper() {
    require(authority.isPositionKeeper(msg.sender), "AuthorityUtils: only position keeper");
    _;
  }

  modifier onlyFastPriceFeed() {
    require(authority.isFastPriceFeed(msg.sender), "AuthorityUtils: only fast price feed");
    _;
  }

  modifier onlyController() {
    require(authority.isController(msg.sender), "AuthorityUtils: only controller");
    _;
  }

  modifier onlyFeeDistributor() {
    require(authority.isFeeDistributor(msg.sender), "AuthorityUtils: only fee distributor");
    _;
  }

  function setAuthority(IOptionsAuthority _newAuthority) external onlyAdmin {
    require(address(_newAuthority) != address(0), "AuthorityUtils: invalid authority address (zero address)");

    authority = _newAuthority;
    emit AuthorityUpdated(_newAuthority);
  }
}