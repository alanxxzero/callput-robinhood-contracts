// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @dev Base USDC's ERC-3009 bytes-signature overload (EOA or token-supported ERC-1271).
interface IReceiveWithAuthorization {
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external;
}
