// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

type PackedBytes32 is bytes32;

library PackedBytes32Helper {
    uint256 internal constant ELEMENT_BITS = 16;
    uint256 internal constant ELEMENT_MASK = 0xFFFF;
    uint256 internal constant ELEMENT_COUNT = 16;

    error OutOfBounds();

    function checkElementCount(uint256 c) internal pure {
        if (c > ELEMENT_COUNT) revert OutOfBounds();
    }

    function get(PackedBytes32 _self, uint256 pos) internal pure returns (uint16 val) {
        assert(pos < ELEMENT_COUNT); // 16 values in bytes32
        unchecked {
            pos *= ELEMENT_BITS; // convert to bit position
        }
        val = uint16(uint256(PackedBytes32.unwrap(_self)) >> pos & ELEMENT_MASK);
        // assembly ("memory-safe") {
        //     let shift := mul(pos, 16)
        //     val := and(shr(shift, _self), 0xffff)
        // }
    }

    function set(PackedBytes32 _self, uint256 pos, uint16 val) internal pure returns (PackedBytes32 res) {
        assert(pos < ELEMENT_COUNT);
        unchecked {
            pos *= ELEMENT_BITS; // convert to bit position
        }
        res = PackedBytes32.wrap(
            bytes32((uint256(PackedBytes32.unwrap(_self)) & ~(ELEMENT_MASK << pos)) | (uint256(val) << pos))
        );

        // assembly ("memory-safe") {
        //     let shift := mul(pos, 16)
        //     res := or(and(_self, not(shl(shift, 0xffff))), shl(shift, val))
        // }
    }

    function unpack(PackedBytes32 _self) internal pure returns (uint16[] memory vals) {
        vals = new uint16[](ELEMENT_COUNT);
        unchecked {
            for (uint8 i = 0; i < 16; ++i) {
                vals[i] = get(_self, i);
            }
        }
        // uint256 shift;
        // for (uint256 i = 0; i < ELEMENT_COUNT; ++i) {
        //     unchecked {
        //         shift = i * ELEMENT_BITS;
        //     }
        //     vals[i] = uint16(uint256(PackedBytes32.unwrap(_self) >> shift));
        // }
    }

    function unpack(PackedBytes32 _self, uint8 length) internal pure returns (uint16[] memory vals) {
        checkElementCount(length);
        vals = new uint16[](length);
        unchecked {
            for (uint8 i = 0; i < length; ++i) {
                vals[i] = get(_self, i);
            }
        }
    }

    function pack(uint16[] memory vals) internal pure returns (PackedBytes32 res) {
        uint256 length = vals.length;
        checkElementCount(length);
        res = PackedBytes32.wrap(0);
        unchecked {
            for (uint8 i = 0; i < length; ++i) {
                res = set(res, i, vals[i]);
            }
        }
    }
}
