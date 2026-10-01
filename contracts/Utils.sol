// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces/IController.sol";

library Utils {
    enum Strategy {
        NotSupported,
        BuyCall,
        SellCall,
        BuyPut,
        SellPut,
        BuyCallSpread,
        SellCallSpread,
        BuyPutSpread,
        SellPutSpread
    }

    uint40 constant SECONDS_PER_DAY = 24 * 60 * 60;
    int40 constant OFFSET19700101 = 2_440_588;

    // Option
    // underlyingAssetIndex - 16-bits
    // expiry - 40-bits
    // strategy - 4-bits

    // length - 2-bits (can be 1, 2, 3, 4)

    // isBuy - 1-bits
    // strikePrice - 46-bits
    // isCall - 1-bits

    // isBuy - 1-bits
    // strikePrice - 46-bits
    // isCall - 1-bits

    // isBuy - 1-bits
    // strikePrice - 46-bits
    // isCall - 1-bits

    // isBuy - 1-bits
    // strikePrice - 46-bits
    // isCall - 1-bits

    // vaultIndex - 2-bits (can be 0, 1, 2, 3)

    function formatOptionTokenId(
        uint16 underlyingAssetIndex,
        uint40 expiry,
        uint8 length,
        bool[4] memory isBuys,
        uint48[4] memory strikePrices,
        bool[4] memory isCalls,
        uint8 vaultIndex
    ) internal pure returns (uint256 optionTokenId) {
        Utils.Strategy strategy;
        bool[4] memory sortedIsBuys;
        uint48[4] memory sortedStrikePrices;
        bool[4] memory sortedIsCalls;

        (
            strategy,
            sortedIsBuys,
            sortedStrikePrices,
            sortedIsCalls
        ) = determineStrategy(length, isBuys, strikePrices, isCalls);

        optionTokenId =
            (uint256(underlyingAssetIndex) << 240) + // // 16 bits
            (uint256(expiry) << 200) + // 40 bits
            (uint256(uint8(strategy)) << 196) + // 4 bits
            (uint256(length - 1) << 194) + // Updated to 2 bits for length
            (uint256(sortedIsBuys[0] ? 1 : 0) << 193) + // 1 bit
            (uint256(sortedStrikePrices[0]) << 147) + // 46 bits
            (uint256(sortedIsCalls[0] ? 1 : 0) << 146) + // 1 bit
            (uint256(sortedIsBuys[1] ? 1 : 0) << 145) + // 1 bit
            (uint256(sortedStrikePrices[1]) << 99) + // 46 bits
            (uint256(sortedIsCalls[1] ? 1 : 0) << 98) + // 1 bit
            (uint256(sortedIsBuys[2] ? 1 : 0) << 97) + // 1 bit
            (uint256(sortedStrikePrices[2]) << 51) + // 46 bits
            (uint256(sortedIsCalls[2] ? 1 : 0) << 50) + // 1 bit
            (uint256(sortedIsBuys[3] ? 1 : 0) << 49) + // 1 bit
            (uint256(sortedStrikePrices[3]) << 3) + // 46 bits
            (uint256(sortedIsCalls[3] ? 1 : 0) << 2) + // 1 bit
            uint256(vaultIndex & 0x3); // Updated to 2 bits for vaultIndex
    }

    function determineStrategy(
        uint8 length,
        bool[4] memory isBuys,
        uint48[4] memory strikePrices,
        bool[4] memory isCalls
    ) internal pure returns (
        Strategy strategy,
        bool[4] memory sortedIsBuys,
        uint48[4] memory sortedStrikePrices,
        bool[4] memory sortedIsCalls
    ) {
        (sortedIsBuys, sortedStrikePrices, sortedIsCalls) = sortOptions(
            length,
            isBuys,
            strikePrices,
            isCalls
        );

        strategy = Strategy.NotSupported;

        if (length == 1) {
            require(sortedStrikePrices[0] != 0, "Utils: Strike price is 0");
            
            if (sortedIsBuys[0] && sortedIsCalls[0]) { // Buy Call (Buy BTC-19JAN24-46000-C)
                strategy = Strategy.BuyCall;
            } else if (!sortedIsBuys[0] && sortedIsCalls[0]) { // Sell Call (Sell BTC-19JAN24-48000-C)
                strategy = Strategy.SellCall;
            } else if (sortedIsBuys[0] && !sortedIsCalls[0]) { // Buy Put (Buy BTC-19JAN24-46000-P)
                strategy = Strategy.BuyPut;
            } else if (!sortedIsBuys[0] && !sortedIsCalls[0]) { // Sell Put (Sell BTC-19JAN24-48000-P)
                strategy = Strategy.SellPut;
            }
        } else if (length == 2) {
            require(sortedStrikePrices[0] != 0 && sortedStrikePrices[1] != 0, "Utils: Strike price is 0");
            require(sortedStrikePrices[0] != sortedStrikePrices[1], "Utils: Strike prices are not unique");

            if (sortedIsCalls[0] == sortedIsCalls[1] && sortedIsBuys[0] != sortedIsBuys[1]) { // Spread
                if (sortedIsCalls[0]) {
                    if (sortedIsBuys[0]) { // Buy Call Spread (Buy BTC-19JAN24-46000-C, Sell BTC-19JAN24-48000-C)
                        strategy = Strategy.BuyCallSpread;
                    } else { // Sell Call Spread (Sell BTC-19JAN24-46000-C, Buy BTC-19JAN24-48000-C)
                        strategy = Strategy.SellCallSpread;
                    }
                } else {
                    if (sortedIsBuys[1]) { // Buy Put Spread (Sell BTC-19JAN24-46000-P, Buy BTC-19JAN24-48000-P)
                        strategy = Strategy.BuyPutSpread;
                    } else { // Sell Put Spread (Buy BTC-19JAN24-46000-P, Sell BTC-19JAN24-48000-P)
                        strategy = Strategy.SellPutSpread;
                    }
                }
            }
        }

        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");

        for (uint256 i = length; i < 4;) {
            sortedIsBuys[i] = false;
            sortedStrikePrices[i] = 0;
            sortedIsCalls[i] = false;
            unchecked { i++; }
        }
    }

    function sortOptions(
        uint8 length,
        bool[4] memory isBuys,
        uint48[4] memory strikePrices,
        bool[4] memory isCalls
    ) internal pure returns (
        bool[4] memory sortedIsBuys,
        uint48[4] memory sortedStrikePrices,
        bool[4] memory sortedIsCalls
    ) {
        uint8[4] memory indices = _sortIndices(strikePrices);

        // apply sorted indices
        for (uint256 i = 0; i < 4;) {
            uint8 sortedIdx = indices[i];
            sortedIsBuys[i] = isBuys[sortedIdx];
            sortedStrikePrices[i] = strikePrices[sortedIdx];
            sortedIsCalls[i] = isCalls[sortedIdx];
            unchecked { i++; }
        }

        // verify length
        _verifyLength(length, sortedStrikePrices);
    }

    function sortOptionsWithIds(
        uint8 length,
        bool[4] memory isBuys,
        bytes32[4] memory optionIds,
        uint48[4] memory strikePrices,
        bool[4] memory isCalls
    ) internal pure returns (
        bool[4] memory sortedIsBuys,
        bytes32[4] memory sortedOptionIds,
        uint48[4] memory sortedStrikePrices,
        bool[4] memory sortedIsCalls
    ) {
        uint8[4] memory indices = _sortIndices(strikePrices);

        // apply sorted indices
        for (uint256 i = 0; i < 4;) {
            uint8 sortedIdx = indices[i];
            sortedIsBuys[i] = isBuys[sortedIdx];
            sortedOptionIds[i] = optionIds[sortedIdx];
            sortedStrikePrices[i] = strikePrices[sortedIdx];
            sortedIsCalls[i] = isCalls[sortedIdx];
            unchecked { i++; }
        }

        // verify length
        _verifyLength(length, sortedStrikePrices);
    }

    function _sortIndices(uint48[4] memory strikePrices) private pure returns (uint8[4] memory indices) {
        // initialize indices
        indices = [0, 1, 2, 3];

        // sort indices based on strike prices
        for (uint256 i = 0; i < 3;) { // bubble sort
            for (uint256 j = 0; j < 3 - i;) {
                uint8 currentIdx = indices[j];
                uint8 nextIdx = indices[j + 1];
                
                if ((strikePrices[currentIdx] > strikePrices[nextIdx] && strikePrices[nextIdx] != 0) || 
                    (strikePrices[currentIdx] == 0 && strikePrices[nextIdx] != 0)) {
                    (indices[j], indices[j + 1]) = (indices[j + 1], indices[j]);
                }

                unchecked { j++; }
            }
            unchecked { i++; }
        }

        return indices;
    }

    function _verifyLength(uint8 length, uint48[4] memory strikePrices) private pure {
        uint8 _length = 0;
        for (uint256 i = 0; i < 4;) {
            if (strikePrices[i] == 0) break;
            _length++;
            unchecked { i++; }
        }
        require(_length == length, "Utils: Length is not correct");
    }

    function parseOptionTokenId(uint256 optionTokenId) internal pure returns (
        uint16 underlyingAssetIndex, // 16 bits
        uint40 expiry, // 40 bits
        Strategy strategy, // 4 bits
        uint8 length, // 2 bit
        bool[4] memory isBuys, // 1 bit each
        uint48[4] memory strikePrices, // 46 bits each
        bool[4] memory isCalls, // 1 bit each
        uint8 vaultIndex // 2 bits
    ) {
        underlyingAssetIndex = uint16((optionTokenId >> 240) & 0xFFFF); // 16 bits
        expiry = uint40((optionTokenId >> 200) & 0xFFFFFFFFFF); // 40 bits
        strategy = Strategy(uint8((optionTokenId >> 196) & 0xF)); // 4 bits
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");

        length = uint8((optionTokenId >> 194) & 0x3) + 1; // 2 bits for length
        
        for (uint256 i = 0; i < 4;) {
            isBuys[i] = ((optionTokenId >> (193 - i * 48)) & 0x1) != 0; // 1 bit each
            strikePrices[i] = uint48((optionTokenId >> (147 - i * 48)) & 0x3FFFFFFFFFFF); // 46 bits each
            isCalls[i] = ((optionTokenId >> (146 - i * 48)) & 0x1) != 0; // 1 bit each
            unchecked { i++; }
        }
        
        vaultIndex = uint8(optionTokenId & 0x3); // 2 bits for vaultIndex
    }

    function getOppositeOptionTokenId(uint256 optionTokenId) internal pure returns (uint256 oppositeOptionTokenId) {
        (
            uint16 underlyingAssetIndex,
            uint40 expiry,
            ,
            uint8 length,
            bool[4] memory isBuys,
            uint48[4] memory strikePrices,
            bool[4] memory isCalls,
            uint8 vaultIndex
        ) = parseOptionTokenId(optionTokenId);
        for(uint256 i = 0; i < length;) {
            isBuys[i] = !isBuys[i];
            unchecked { i++; }
        }

        oppositeOptionTokenId = formatOptionTokenId(underlyingAssetIndex, expiry, length, isBuys, strikePrices, isCalls, vaultIndex);
    }

    function getOppositeStrategy(Strategy strategy) internal pure returns (Strategy) {
        if (strategy == Strategy.BuyCall) {
            return Strategy.SellCall;
        } else if (strategy == Strategy.SellCall) {
            return Strategy.BuyCall;
        } else if (strategy == Strategy.BuyPut) {
            return Strategy.SellPut;
        } else if (strategy == Strategy.SellPut) {
            return Strategy.BuyPut;
        } else if (strategy == Strategy.BuyCallSpread) {
            return Strategy.SellCallSpread;
        } else if (strategy == Strategy.SellCallSpread) {
            return Strategy.BuyCallSpread;
        } else if (strategy == Strategy.BuyPutSpread) {
            return Strategy.SellPutSpread;
        } else if (strategy == Strategy.SellPutSpread) {
            return Strategy.BuyPutSpread;
        } else {
            revert("Utils: Invalid strategy");
        }
    }

    function getUnderlyingAssetIndexByOptionTokenId(uint256 optionTokenId) internal pure returns (uint16) {
        return uint16((optionTokenId >> 240) & 0xFFFF);
    }

    function getExpiryByOptionTokenId(uint256 optionTokenId) internal pure returns (uint40) {
        return uint40((optionTokenId >> 200) & 0xFFFFFFFFFF);
    }

    function getStrategyByOptionTokenId(uint256 optionTokenId) internal pure returns (Strategy) {
        Strategy strategy = Strategy(uint8((optionTokenId >> 196) & 0xF)); // 4 bits
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");
        return strategy;
    }

    function getVaultIndexByOptionTokenId(uint256 optionTokenId) internal pure returns (uint8) {
        return uint8(optionTokenId & 0x3);
    }

    function getLengthByStrategy(Strategy strategy) internal pure returns (uint8 length) {
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");

        if (isNaked(strategy)) {
            length = 1;
        } if (isSpread(strategy)) {
            length = 2;
        }
    }

    function isBuy(Strategy strategy) internal pure returns (bool) {
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");
        return strategy == Strategy.BuyCall || strategy == Strategy.BuyPut || strategy == Strategy.BuyCallSpread || strategy == Strategy.BuyPutSpread;
    }

    function isSell(Strategy strategy) internal pure returns (bool) {
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");
        return strategy == Strategy.SellCall || strategy == Strategy.SellPut || strategy == Strategy.SellCallSpread || strategy == Strategy.SellPutSpread;
    }

    function isCall(Strategy strategy) internal pure returns (bool) {
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");
        return strategy == Strategy.BuyCall || strategy == Strategy.SellCall || strategy == Strategy.BuyCallSpread || strategy == Strategy.SellCallSpread;
    }

    function isPut(Strategy strategy) internal pure returns (bool) {
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");
        return strategy == Strategy.BuyPut || strategy == Strategy.SellPut || strategy == Strategy.BuyPutSpread || strategy == Strategy.SellPutSpread;
    }

    function isNaked(Strategy strategy) internal pure returns (bool) {
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");
        return strategy == Strategy.BuyCall || strategy == Strategy.SellCall || strategy == Strategy.BuyPut || strategy == Strategy.SellPut;
    }

    function isSpread(Strategy strategy) internal pure returns (bool) {
        require(strategy != Strategy.NotSupported, "Utils: Invalid strategy");
        return strategy == Strategy.BuyCallSpread || strategy == Strategy.SellCallSpread || strategy == Strategy.BuyPutSpread || strategy == Strategy.SellPutSpread;
    }
}
