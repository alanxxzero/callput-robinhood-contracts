// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {ITradingAccountSessions as S} from "./interfaces/ITradingAccountSessions.sol";

/// @dev EIP712 struct hashes only. No state, signature recovery or authorization decisions.
library SessionHash {
    bytes32 internal constant GRANT = keccak256(
        "Grant(address signer,uint256 nonce,uint256 epoch,uint48 validAfter,uint48 validUntil,uint16[] underlyings,uint16 strategies,uint256 maxAmountPerOpen,uint256 maxAmount,uint32 maxOpens,uint32 maxCloses,uint256 maxFeePerTrade,uint256 maxFees)"
    );
    bytes32 internal constant OPEN = keccak256(
        "Open(uint16 underlyingAssetIndex,uint8 length,bool[4] isBuys,bytes32[4] optionIds,bool[4] isCalls,uint256 minSize,uint256 amountIn)"
    );
    bytes32 internal constant CLOSE =
        keccak256("Close(uint16 underlyingAssetIndex,uint256 optionTokenId,uint256 size,uint256 minAmountOut)");
    bytes32 internal constant OPEN_INTENT = keccak256(
        "OpenIntent(bytes32 sessionId,uint256 epoch,uint256 nonce,uint48 deadline,uint8 source,Open params)Open(uint16 underlyingAssetIndex,uint8 length,bool[4] isBuys,bytes32[4] optionIds,bool[4] isCalls,uint256 minSize,uint256 amountIn)"
    );
    bytes32 internal constant CLOSE_INTENT = keccak256(
        "CloseIntent(bytes32 sessionId,uint256 epoch,uint256 nonce,uint48 deadline,uint8 source,Close params)Close(uint16 underlyingAssetIndex,uint256 optionTokenId,uint256 size,uint256 minAmountOut)"
    );
    bytes32 internal constant WITHDRAWAL = keccak256(
        "Withdrawal(uint8 kind,address token,uint256 id,uint256 amount,address to,uint256 epoch,uint256 nonce,uint48 deadline)"
    );
    bytes32 internal constant REVOKE =
        keccak256("RevokeSession(bytes32 sessionId,uint256 epoch,uint256 nonce,uint48 deadline)");
    bytes32 internal constant EPOCH =
        keccak256("InvalidateEpoch(uint256 epoch,uint256 newEpoch,uint256 nonce,uint48 deadline)");

    function grant(S.Grant calldata g) internal pure returns (bytes32) {
        // EIP712 array elements are 32-byte encoded; uint16 packed bytes would be incorrect.
        bytes32[] memory assets = new bytes32[](g.underlyings.length);
        for (uint256 i; i < assets.length; ++i) {
            assets[i] = bytes32(uint256(g.underlyings[i]));
        }
        return keccak256(
            abi.encode(
                GRANT,
                g.signer,
                g.nonce,
                g.epoch,
                g.validAfter,
                g.validUntil,
                keccak256(abi.encodePacked(assets)),
                g.strategies,
                g.maxAmountPerOpen,
                g.maxAmount,
                g.maxOpens,
                g.maxCloses,
                g.maxFeePerTrade,
                g.maxFees
            )
        );
    }

    function open(S.Open calldata p) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                OPEN,
                p.underlyingAssetIndex,
                p.length,
                keccak256(abi.encode(p.isBuys)),
                keccak256(abi.encode(p.optionIds)),
                keccak256(abi.encode(p.isCalls)),
                p.minSize,
                p.amountIn
            )
        );
    }

    function close(S.Close calldata p) internal pure returns (bytes32) {
        return keccak256(abi.encode(CLOSE, p.underlyingAssetIndex, p.optionTokenId, p.size, p.minAmountOut));
    }

    function intent(S.Intent calldata i, bytes32 paramsHash, bool isOpen) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                isOpen ? OPEN_INTENT : CLOSE_INTENT,
                i.sessionId,
                i.epoch,
                i.nonce,
                i.deadline,
                i.source,
                paramsHash
            )
        );
    }

    function withdrawal(S.Withdrawal calldata p) internal pure returns (bytes32) {
        return keccak256(abi.encode(WITHDRAWAL, p));
    }
}
