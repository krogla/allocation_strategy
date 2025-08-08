// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

library PackedUint256 {
    using PackedHelper for uint256;

    function get16(uint256 x, uint8 p) internal pure returns (uint16 v) {
        return uint16(x._unpack(p, 16));
        // assembly ("memory-safe") {
        //     let s := shl(4, p) // p * 16
        //     v := and(shr(s, x), 0xffff)
        // }
    }

    function set16(uint256 x, uint8 p, uint16 v) internal pure returns (uint256 r) {
        return x._pack(p, 16, v);
        // assembly ("memory-safe") {
        //     let s := shl(4, p) // p * 16
        //     r := or(and(x, not(shl(s, 0xffff))), shl(s, v))
        // }
    }

    function get32(uint256 x, uint8 p) internal pure returns (uint32 v) {
        return uint32(x._unpack(p, 32));
    }

    function set32(uint256 x, uint8 p, uint32 v) internal pure returns (uint256) {
        return x._pack(p, 32, v);
    }

    function pack16(uint16[] memory vs) internal pure returns (uint256 x) {
        for (uint8 i = 0; i < vs.length; ++i) {
            x = x._pack(i, 16, vs[i]);
        }
    }

    function unpack16(uint256 x) internal pure returns (uint16[] memory vs) {
        vs = new uint16[](16);
        for (uint8 i = 0; i < 16; ++i) {
            vs[i] = uint16(x._unpack(i, 16));
        }
    }
}

/// @notice Provides an interface for gas-efficient store any values tightly packed into one bytes32
library PackedHelper {
    /// @dev Returns value stored on position `pos` with `bits`-length mask
    function _unpack(uint256 x, uint8 pos, uint8 bits) internal pure returns (uint256 r) {
        // unchecked {
        //     pos *= bits; // convert to bit position
        // }
        // return x >> pos & _mask(bits);

        assembly ("memory-safe") {
            let p := mul(pos, bits)
            let mask := shr(sub(256, bits), not(0))
            r := and(shr(p, x), mask)
        }
    }

    /// @dev Writes value passed in `x` variable on position `pos` with `bits`-length mask.
    function _pack(uint256 x, uint8 pos, uint8 bits, uint256 v) internal pure returns (uint256 r) {
        // uint256 mask = _mask(bits);
        // unchecked {
        //     pos *= bits; // convert to bit position
        // }
        // return (x & ~(mask << pos)) | ((v & mask) << pos);
        assembly ("memory-safe") {
            let p := mul(pos, bits)
            let mask := shr(sub(256, bits), not(0))
            let slotMask := shl(p, mask) // (mask << p)
            r := or(and(x, not(slotMask)), shl(p, and(v, mask)))
        }
    }

    // function _mask(uint8 bits) internal pure returns (uint256 mask) {
    //     unchecked {
    //         mask = ~uint256(0) >> (256 - bits);
    //     }
    // }
}
