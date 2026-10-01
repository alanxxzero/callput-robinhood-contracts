// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IVaultPriceFeed {
    function setTokenConfig(address _token, bool _isSupported, bool _isStrictStable) external;

    function getSettlePrice(address _token, uint256 _expiry) external view returns (uint256);
    function getAPV(address _vault) external view returns (uint256);
    function getPVAndSign(address _vault) external view returns (uint256, bool);
    function getMarkPrice(uint256 _optionTokenId, uint256 _requestIndex) external view returns (uint256);
    function getRiskPremium(uint256 _optionTokenId, uint256 _requestIndex) external view returns (uint256);
    function getMarkPriceAndRiskPremium(uint256 _optionTokenId, uint256 _requestIndex) external view returns (uint256, uint256);
    function getExecutionPrice(uint256 _optionTokenId, uint256 _requestIndex, bool _addRiskPremium) external view returns (uint256);    

    function getSpotPrice(address _token, bool _maximise) external view returns (uint256);
    function getOraclePrice(address _token, bool _maximise) external view returns (uint256);
    
    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external;
    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external;
    function setMinMarkPrice(uint16 _underlyingAssetIndex, uint256 _minMarkPrice) external;
}
