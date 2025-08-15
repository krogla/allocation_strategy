// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

library BitMask16 {
    /// @notice Set bit in bitmask
    function setBit(uint16 m, uint8 i) internal pure returns (uint16) {
        return m | (uint16(1) << i);
    }

    function clearBit(uint16 m, uint8 i) internal pure returns (uint16) {
        return m & ~(uint16(1) << i);
    }

    /// @notice Check if bit is set
    function isBitSet(uint16 m, uint8 i) internal pure returns (bool) {
        return (m & (uint16(1) << i)) != 0;
    }

    /// @notice Convert bitmask to array
    function bitsToValues(uint16 m) internal pure returns (uint8[] memory values) {
        // Create array with metrics
        values = new uint8[](countBits(m));
        uint256 index = 0;
        for (uint8 i = 0; i < 16; ++i) {
            if (isBitSet(m, i)) {
                values[index++] = i;
            }
        }
    }

    function countBits(uint16 m) internal pure returns (uint8 count) {
        unchecked {
            m = m - ((m >> 1) & 0x5555); // 0b0101010101010101
            m = (m & 0x3333) + ((m >> 2) & 0x3333); // group 2 bits, 0b0011001100110011
            m = (m + (m >> 4)) & 0x0F0F; // sum 4 groups, 0b0000111100001111
            m = m + (m >> 8); // sum all nibbles
            count = uint8(m & 0x001F); // max 16 bits → 5 bits are enough (0..16)
        }
    }
}
