// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IUSDG {
    function setVault(address _vault, bool _isVault) external;
    function mint(address _account, uint256 _amount) external;
    function burn(address _account, uint256 _amount) external;
}
