// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IVault {
    function whitelistedTokensLength() external view returns (uint256);
    function getWhitelistedTokens(uint256 index) external view returns (address);
    function isWhitelistedToken(address token) external view returns (bool);
}

contract WhitelistTest {
    address public vault;

    constructor(address _vault) {
        vault = _vault;
    }

    function getWhitelistedTokens() public view returns (address[] memory) {
        uint256 length = IVault(vault).whitelistedTokensLength();
        address[] memory whitelistedTokens = new address[](length);

        uint256 counter = 0;

        for (uint256 i = 0; i < length;) {
            address token = IVault(vault).getWhitelistedTokens(i);
            bool isWhitelisted = IVault(vault).isWhitelistedToken(token);

            if (isWhitelisted) {
                whitelistedTokens[counter] = token;
                counter++;
            }

            unchecked { i++; }
        }

        assembly {
            mstore(whitelistedTokens, counter)
        }

        return whitelistedTokens;
    }

    // 테스트용 함수: 임의의 배열을 만들어서 mstore 사용 전후로 배열 길이를 출력
    function testMstore() public pure returns (uint256 beforeLength, uint256 afterLength) {
        address[] memory testArray = new address[](5);
        testArray[0] = 0x0000000000000000000000000000000000000001;
        testArray[1] = 0x0000000000000000000000000000000000000002;
        testArray[2] = 0x0000000000000000000000000000000000000003;
        testArray[3] = 0x0000000000000000000000000000000000000004;
        testArray[4] = 0x0000000000000000000000000000000000000005;

        beforeLength = testArray.length;

        uint256 newLength = 3;

        assembly {
            mstore(testArray, newLength)
        }

        afterLength = testArray.length;

        return (beforeLength, afterLength);
    }
}