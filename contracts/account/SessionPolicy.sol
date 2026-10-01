// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

/// @dev Canonical two-leg spread encoding from Utils.formatOptionTokenId. No four-leg sorting or
///      token generation is needed here: stored positions are already sorted. Differential tests
///      compare this check with the core formatter, including both directions/call and put spreads.
library SessionPolicy {
    function canonicalSpread(uint256 id) internal pure returns (bool) {
        // bits 194..195 encode length-1. Bits 2..97 are the unused third/fourth legs.
        if (((id >> 194) & 3) != 1 || (id & (((uint256(1) << 96) - 1) << 2)) != 0) return false;
        uint256 strikeMask = (uint256(1) << 46) - 1;
        uint256 low = (id >> 147) & strikeMask;
        uint256 high = (id >> 99) & strikeMask;
        if (low == 0 || low >= high) return false;
        bool buyLow = ((id >> 193) & 1) != 0;
        bool buyHigh = ((id >> 145) & 1) != 0;
        bool callLow = ((id >> 146) & 1) != 0;
        bool callHigh = ((id >> 98) & 1) != 0;
        if (buyLow == buyHigh || callLow != callHigh) return false;
        uint256 expected = callLow ? (buyLow ? 5 : 6) : (buyLow ? 8 : 7);
        return ((id >> 196) & 15) == expected;
    }
}
