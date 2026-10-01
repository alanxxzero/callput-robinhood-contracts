// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IReferral {
  function setReferralRate(uint256 _discountRate, uint256 _feeRebateRate) external;

  function addToAffiliates(address _account, uint256 _discountRate, uint256 _feeRebateRate) external returns (bool);
  function removeFromAffiliates(address _account) external returns (bool);
  function addToAffiliatesInBatch(address[] memory _accounts, uint256[] memory _discountRates, uint256[] memory _feeRebateRate) external;
  function removeFromAffiliatesInBatch(address[] memory _accounts) external;
  function isAffiliates(address _account) external view returns (bool);

  function setPartner(address _account, bool _isPartner, uint256 _discountRate, uint256 _term) external;

  function getRateInfo(address _account) external view returns (uint256, address, uint256);
}
