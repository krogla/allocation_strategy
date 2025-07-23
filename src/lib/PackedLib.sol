// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

type PackedBytes32 is bytes32;

/// @notice Provides an interface for gas-efficient store of two uint16 values in one uint32
library PackedUint32x16 {
    function unpack(uint32 _self) internal pure returns (uint16 a, uint16 b) {
        a = uint16(_self >> 16);
        b = uint16(_self);
    }

    function pack(uint16 a, uint16 b) internal pure returns (uint32) {
        return (uint32(a) << 16) | uint32(b);
    }
}

/// @notice Provides an interface for gas-efficient store any values tightly packed into one bytes32
library PackedBytes32Helper {
    /// @dev Returns value stored on position `pos` with `bits`-length mask
    function _unpack(PackedBytes32 _self, uint8 pos, uint8 bits) internal pure returns (bytes32) {
        return PackedBytes32.unwrap(_self) >> pos & _mask(bits);
    }

    /// @dev Writes value passed in `x` variable on position `pos` with `bits`-length mask.
    function _pack(PackedBytes32 _self, uint8 pos, uint8 bits, bytes32 x) internal pure returns (PackedBytes32) {
        bytes32 mask = _mask(bits);
        return PackedBytes32.wrap(PackedBytes32.unwrap(_self) & ~(mask << pos) | ((x & mask) << pos));
    }

    // function _unpack(bytes32 _self, uint8 pos, uint8 bits) internal pure returns (bytes32) {
    //     return _self >> pos & _mask(bits);
    // }

    // function _pack(bytes32 _self, uint8 pos, uint8 bits, bytes32 x) internal pure returns (bytes32) {
    //     bytes32 mask = _mask(bits);
    //     return _self & ~(mask << pos) | ((x & mask) << pos);
    // }

    function _mask(uint8 bits) internal pure returns (bytes32 mask) {
        unchecked {
            mask = ~bytes32(0) >> (256 - bits);
        }
    }
}

library PackedBytes32x16 {
    using PackedBytes32Helper for PackedBytes32;

    uint8 constant BITS = 16; // bits in each value

    function unpack(PackedBytes32 _self, uint8 pos) internal pure returns (uint16) {
        assert(pos < 16); // 16 values in bytes32
        return uint16(uint256(_self._unpack(pos * BITS, BITS)));
    }

    function pack(PackedBytes32 _self, uint8 pos, uint16 x) internal pure returns (PackedBytes32) {
        assert(pos < 16);
        return _self._pack(pos * BITS, BITS, bytes32(uint256(x)));
    }
}

library PackedBytes32x16Array {
    using PackedBytes32x16 for PackedBytes32;

    // struct DataStorage {
    //     PackedBytes32[] _data; // каждый элемент ровно 32 байта (packed)
    // }

    function set(PackedBytes32[] storage _self, uint16 index, PackedBytes32 val) internal {
        _self[index] = val;
    }

    function add(PackedBytes32[] storage _self, PackedBytes32 val) internal {
        _self.push(val);
    }

    function del(PackedBytes32[] storage _self) internal returns (PackedBytes32 val) {
        val = _self[_self.length - 1];
        _self.pop();
    }

    function get(PackedBytes32[] storage _self, uint16 index) internal view returns (PackedBytes32 val) {
        val = _self[index];
    }

    function pluck(PackedBytes32[] storage self, uint8 pos) internal view returns (uint16[] memory res) {
        uint256 length = self.length;
        res = new uint16[](length);

        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                res[i] = self[i].unpack(pos);
            }
        }
    }

    // function getAll(PackedBytes32[] storage _self) internal view returns (PackedBytes32[] memory) {
    //     return _self;
    // }

    // function getStorage(bytes32 _position) internal view returns (PackedBytes32[] storage) {
    //     return _getDataStorage(_position)._data;
    // }

    // function _getDataStorage(bytes32 _position) private pure returns (DataStorage storage $) {
    //     assembly {
    //         $.slot := _position
    //     }
    // }
}
