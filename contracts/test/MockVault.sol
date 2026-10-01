// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

contract MockVault {
    address[] public whitelistedTokens;
    mapping(address => bool) public isWhitelistedToken;

    constructor() {
        whitelistedTokens.push(0x0000000000000000000000000000000000000001);
        whitelistedTokens.push(0x0000000000000000000000000000000000000002);
        whitelistedTokens.push(0x0000000000000000000000000000000000000003);

        isWhitelistedToken[0x0000000000000000000000000000000000000001] = true;
        isWhitelistedToken[0x0000000000000000000000000000000000000002] = true;
        isWhitelistedToken[0x0000000000000000000000000000000000000003] = true;
    }

    function whitelistedTokensLength() external view returns (uint256) {
        return whitelistedTokens.length;
    }

    function getWhitelistedTokens(uint256 index) external view returns (address) {
        return whitelistedTokens[index];
    }

    function setWhitelistedToken(address token, bool value) external {
        isWhitelistedToken[token] = value;
    }
}
