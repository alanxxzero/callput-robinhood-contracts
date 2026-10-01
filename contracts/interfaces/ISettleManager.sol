// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface ISettleManager {
    function settlePosition(
        address[] memory _path,
        uint16 _underlyingAssetIndex,
        uint256 _optionTokenId,
        uint256 _minOutWhenSwap,
        bool _withdrawETH
    ) external returns (uint256);

    function settlePositions(
        address[][] memory _paths,
        uint16 _underlyingAssetIndex,
        uint256[] memory _optionTokenIds,
        uint256[] memory _minOutWhenSwaps,
        bool _withdrawNAT
    ) external;

}
