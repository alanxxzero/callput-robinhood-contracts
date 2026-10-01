// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IOptionsToken {
      function name() external view returns (string memory);
      function underlyingAsset() external view returns (address);
      function decimals() external view returns (uint8);
      function mint(address account, uint256 id, uint256 amount) external;
      function burn(address account, uint256 id, uint256 amount) external;
}