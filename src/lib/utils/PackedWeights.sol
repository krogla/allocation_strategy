// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {PackedUint256} from "./PackedUint256.sol";

// packed weights for all strategies, 8 uint32 in one bytes32
library PackedWeights {
    using PackedUint256 for uint256;

    struct Packed2 {
        uint256 slotA;
        uint256 slotB;
    }

    function get32(Packed2 memory x, uint8 p) internal pure returns (uint32 v) {
        // w0..w7 in slotA, w8..w15 in slotB (8 each)
        return (p < 8) ? x.slotA.get32(p) : x.slotB.get32(p - 8);
    }

    function set32(Packed2 memory x, uint8 p, uint32 v) internal pure {
        // w0..w7 в slotA, w8..w15 в slotB (8 each)
        if (p < 8) {
            x.slotA = x.slotA.set32(p, v);
        } else {
            x.slotB = x.slotB.set32(p - 8, v);
        }
    }

    function pack32(uint32[] memory vs) internal pure returns (Packed2 memory x) {
        for (uint8 i = 0; i < vs.length; ++i) {
            set32(x, i, vs[i]);
        }
    }

    function unpack32(Packed2 memory x) internal pure returns (uint32[] memory vs) {
        vs = new uint32[](16);
        for (uint8 i = 0; i < 16; ++i) {
            vs[i] = get32(x, i);
        }
    }
}
