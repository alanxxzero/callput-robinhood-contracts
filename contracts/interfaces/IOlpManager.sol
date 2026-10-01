// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IVault.sol";
import "./IVaultUtils.sol";
import "../oracles/interfaces/IVaultPriceFeed.sol";

interface IOlpManager {
    function olp() external view returns (address);
    function usdg() external view returns (address);
    function vault() external view returns (IVault);
    function vaultUtils() external view returns (IVaultUtils);
    function vaultPriceFeed() external view returns (IVaultPriceFeed);
    function cooldownDuration() external returns (uint256);
    function setLastAddedAt(address _account, uint256 _timestamp) external;
    function getPrice(bool _maximise) external view returns (uint256);
    function getAumInUsdg(bool _maximise) external view returns (uint256);
    function getAum(bool _maximise) external view returns (uint256);
    function getTotalOlpAssetUsd(bool _maximise) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);
    function getOlpAssetUsd(address _token, bool _maximise) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);
    function getOlpAssetAmounts(address _token) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);
    function getOlpMpRpReleaseUsd(bool _maximise) external view returns (uint256, uint256);
    function isWhitelistedToken(address _token) external view returns (bool);
    function isEnabledToken(address _token) external view returns (bool);
    function isCooldownPassed(address _account) external view returns (bool);
    function lastAddedAt(address _account) external returns (uint256);
    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minOlp) external returns (uint256);
    function addLiquidityForAccount(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minOlp) external returns (uint256);
    function removeLiquidity(address _tokenOut, uint256 _olpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function removeLiquidityForAccount(address _account, address _tokenOut, uint256 _olpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function setCooldownDuration(uint256 _cooldownDuration) external;
}
