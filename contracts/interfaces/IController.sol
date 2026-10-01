// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../Utils.sol";

interface IController {
    function maxGasPrice() external view returns (uint256);
    function isNATSupported() external view returns (bool);

    function setVault(uint8 _vaultIndex, address _vault) external;

    function getVaults() external view returns (address[3] memory);
    function getVaultAddressByIndex(uint8 _vaultIndex) external view returns (address);
    function getVaultAddressByOptionTokenId(uint256 _optionTokenId) external view returns (address);
    function getVaultIndexByTimeGap(uint40 _standardTime, uint40 _expiry) external view returns (uint8);
    function isVault(address _account) external view returns (bool);
    function getSpotPriceByUnderlyingAssetIndex(uint16 _underlyingAssetIndex) external view returns (uint256);

    function getNotionalVolume(uint16[] memory _underlyingAssetIndexes) external view returns (uint256 acc);
    function getNotionalVolumeByOptionType(uint16[] memory _underlyingAssetIndexes, bool _isCall) external view returns (uint256 acc);
    function getTotalExecutionPrice(uint16[] memory _underlyingAssetIndexes) external view returns (uint256 acc);
    function getTotalExecutionPriceByOptionType(uint16[] memory _underlyingAssetIndexes, bool _isCall) external view returns (uint256 acc);
    function validateNATSupport() external view;

    function addPlugin(address _plugin) external;

    function pluginERC20Transfer(address _token, address _account, address _receiver, uint256 _amount) external;
    function pluginERC1155Transfer(address _optionsToken, address _account, address _receiver, uint256 _optionTokenId, uint256 _amount) external;
    
    function pluginOpenPosition(
        address _account,
        uint256 _requestIndex,
        address _quoteToken,
        uint256 _optionTokenId,
        uint256 _minSize,
        address _receiver,
        address _vault
    ) external returns (uint256 sizeOut, uint256 executionPrice, uint256 amountOut);
    
    function pluginClosePosition(
        address _account,
        uint256 _requestIndex,
        uint256 _optionTokenId,
        uint256 _size,
        address _quoteToken,
        uint256 _minAmountOut,
        address _receiver,
        address _targetVault
    ) external returns (uint256 amountOut, uint256 executionPrice);

    function pluginSettlePosition(
        address _account,
        address _quoteToken,
        uint256 _optionTokenId,
        uint256 _size,
        address _receiver
    ) external returns (uint256, uint256);

    function pluginClearPosition(
        uint256[] memory _optionTokenIds,
        address _vault
    ) external;
    
    function swap(address _vault, address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver) external returns (uint256);

    function validateOpenPosition(
        uint16 _underlyingAssetIndex,
        uint8 _length,
        bool[4] memory _isBuys,
        bytes32[4] memory _optionIds,
        bool[4] memory _isCalls
    ) external view returns (uint40, uint256, bytes32[4] memory);
}
