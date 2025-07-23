// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {PackedUint32x16} from "./PackedLib.sol";

type ValueCount is uint32;
// struct ValueCount {
//     uint16 v; // v in range 0…10_000 inclusive
//     uint16 n; // count of v in the original array
// }

library ValueCountHelper {
    using PackedUint32x16 for uint32;

    function make(uint16 v, uint16 n) internal pure returns (ValueCount) {
        return ValueCount.wrap(PackedUint32x16.pack(v, n));
        // return ValueCount.wrap((uint32(v) << 16) | uint32(n));
    }

    function get(ValueCount _self) internal pure returns (uint16 v, uint16 n) {
        return PackedUint32x16.unpack(ValueCount.unwrap(_self));
        // uint32 v = ValueCount.unwrap(_self);
        // v = uint16(v >> 16);
        // n = uint16(v);
    }

    // function set(ValueCount _self, uint16 v, uint16 n) internal pure returns (ValueCount) {
    //     return make(v, n);
    // }

    // function setV(ValueCount _self, uint16 v) internal pure returns (ValueCount) {
    //     (, uint16 n) = get(_self);
    //     return make(v, n);
    // }

    // function setN(ValueCount _self, uint16 n) internal pure returns (ValueCount) {
    //     (uint16 v,) = get(_self);
    //     return make(v, n);
    // }

    // function getV(ValueCount _self) internal pure returns (uint16) {
    //     return uint16(ValueCount.unwrap(_self) >> 16);
    // }

    // function getN(ValueCount _self) internal pure returns (uint16) {
    //     return uint16(ValueCount.unwrap(_self));
    // }
}
/// @title WeightsLib
/// @notice Provides a library for calculating weights based on values statistics
/// @dev Supports exponential and linear distributions, compresses uint16 arrays into ValueCount structures
/// @dev Uses 32.32 fixed-point arithmetic for coefficients, ensuring precision in calculations
/// @dev Based on the following constraints:
///      1. Parameter values must be within range 0 to 10_000 (inclusive)
///      2. Array length must not exceed 65_536 elements (allowing uint16 for values and indices)
///      Note: In practice, the number of elements should be limited to a smaller number (e.g. 1000)
///      to maintain reasonable gas consumption.

library WeightsLib {
    using ValueCountHelper for ValueCount;

    uint16 internal constant MAX_VALUE = 10_000; // i.e. 0…10_000 inclusive
    uint16 internal constant MAX_COUNT = 1_000; // max number of the input items
    uint64 internal constant SCALE = 1 << 32; // i.e. 1.0 in 32.32

    /// @notice Calculate linear weights based on vals
    /// @dev Compresses input vals using _compress and calculates linear weights
    /// @param vals Array of uint16 vals to process
    /// @return idxs Array of reference indices
    /// @return valCounts Compressed vals array
    /// @return weights Array of calculated linear coefficients
    function getValueWeights(uint16[] memory vals)
        internal
        pure
        returns (uint16[] memory idxs, ValueCount[] memory valCounts, uint64[] memory weights)
    {
        (idxs, valCounts) = _compress(vals);
        weights = calcWeights(valCounts);
    }

    /// @notice Calculate exponential weights based on vals and decay rate
    /// @dev Compresses input vals using _compress and calculates exponential weights
    /// @param vals Array of uint16 vals to process
    /// @param r Decay rate as uint64
    /// @return idxs Array of reference indices
    /// @return valCounts Compressed vals array
    /// @return weights Array of calculated exponential coefficients
    function getValueWeightsExp(uint16[] memory vals, uint64 r)
        internal
        pure
        returns (uint16[] memory idxs, ValueCount[] memory valCounts, uint64[] memory weights)
    {
        (idxs, valCounts) = _compress(vals);
        weights = calcWeightsExp(valCounts, r);
    }

    /// @notice proportional direct distribution
    /// @dev v ↑ => coeff ↑ ; 0 → 0
    function calcWeights(ValueCount[] memory valCounts) internal pure returns (uint64[] memory) {
        return _calcWeights(valCounts, 0, _calcWeightLinear);
    }

    /// @dev exponential distribution
    /// @notice returns weights[] aligned with uniques[]; each coeff is 32.32 and sums to SCALE (i.e. 1)
    function calcWeightsExp(ValueCount[] memory valCounts, uint64 r) internal pure returns (uint64[] memory) {
        return _calcWeights(valCounts, r, _calcWeightExp);
    }

    /// TODO?
    /// @notice proportional inverse distribution
    /// @dev v ↑ => coeff ↓ ; 0 → 0
    // function weightsInverse(ValueCount[] memory valCounts) internal pure returns (uint64[] memory) {
    //        return _calcWeights(valCounts, 0, _calcWeightInverse);
    // }

    /// @dev calculates coefficients for given v statistics
    /// @param valCounts array of v statistics, i.e. v and count pairs
    /// @param r 32.32 fixed-point number, used for exponential weight calculation,
    function _calcWeights(
        ValueCount[] memory valCounts,
        uint64 r,
        function(uint16, uint64) internal pure returns (uint64) __calcValueWeight
    ) internal pure returns (uint64[] memory weights32x32) {
        uint256 l = valCounts.length;
        if (l == 0) return new uint64[](0);

        uint64[] memory weights = new uint64[](l);
        uint128 total;

        unchecked {
            for (uint256 i; i < l; ++i) {
                (uint16 v, uint16 n) = valCounts[i].get();
                uint64 w = __calcValueWeight(v, r);
                if (w > 0) {
                    total += w * n;
                }
                weights[i] = w;
            }
        }
        return _normalizeWeights(weights, total);
    }

    /// @dev rewrites vals in weights32x32
    function _normalizeWeights(uint64[] memory weights, uint128 total)
        internal
        pure
        returns (uint64[] memory weights32x32)
    {
        uint256 l = weights.length;
        weights32x32 = new uint64[](l);
        // if all vals = 0 → all weights = 0 → all weights = 0
        if (total == 0) return weights32x32;
        // normalize to 1.0 in 32.32
        unchecked {
            for (uint256 i; i < l; ++i) {
                weights32x32[i] = uint64((uint128(weights[i]) << 32) / total); // ≤ SCALE
            }
        }
    }

    /// @dev compresses uint16[] into ValueCount[] with v and count
    /// @notice vals are 0…10_000 inclusive; count is how many times v appears in the array
    function _compress(uint16[] memory vals)
        internal
        pure
        returns (uint16[] memory idxs, ValueCount[] memory valCounts)
    {
        // first pass: count frequencies
        uint256 l = vals.length;
        assert(l <= MAX_COUNT); // ensure we do not exceed the items count limit

        // / @dev in 1st loop we use freqMap as usual uint32 array, while filling unique value's counts,
        // / but unique value count will not exceed input array length, so it fits into uint16
        // / due to this we can safely cast freqMap to PackedUint32x16 in 2nd loop,
        // / where we put mapping index for each unique value as second part of PackedUint32x16
        uint16[MAX_VALUE + 1] memory freqMap; // 0…10_000 inclusive
        uint16 uniq;

        unchecked {
            for (uint256 i; i < l; ++i) {
                uint16 v = vals[i];
                /// @dev guarantee that value are in range 0..10_000
                assert(v <= MAX_VALUE);
                uint16 n = freqMap[v];
                uniq += (n == 0 ? 1 : 0);
                freqMap[v] = n + 1;
            }
        }

        // second pass: collect resulting pairs
        valCounts = new ValueCount[](uniq);
        uint16 j;

        unchecked {
            for (uint16 v = 0; v <= MAX_VALUE; ++v) {
                uint16 n = freqMap[v];
                if (n != 0) {
                    valCounts[j] = ValueCountHelper.make(v, n);
                    /// @dev overwrite freqMap[v] with index j, i.e. save position of the unique value in valCounts
                    freqMap[v] = j;
                    if (++j == uniq) break; // all unique vals are collected
                }
            }
        }

        /* fill indexes */
        idxs = new uint16[](l);
        unchecked {
            for (uint256 i; i < l; ++i) {
                // exists guaranteed, as we checked it in the previous loop
                idxs[i] = freqMap[vals[i]];
            }
        }
    }

    // weight calculation functions

    function _calcWeightExp(uint16 v, uint64 r) internal pure returns (uint64 w) {
        if (v == 0) {
            return 0; // zero weight
        }
        // w = r^v using fast exponentiation by squaring (log2(10k)=14 max squaring)
        w = _pow32(r, v);
    }

    function _calcWeightLinear(uint16 v, uint64) internal pure returns (uint64 w) {
        if (v == 0) {
            return 0; // zero weight
        }
        // w = v
        w = v;
    }

    // function _calcWeightPropInv(uint64, uint16 v, uint16 vMax, uint16 vMin) internal pure returns (uint64 w) {
    //     if (v == 0) {
    //         return 0; // zero weight
    //     }
    //     w = uint64(vMax - v) + 1; // ≥1
    // }

    // helpers

    /// power in 32.32, exponent is uint16 (0…10k) — 14 squarings max
    function _pow32(uint64 base, uint16 exp) private pure returns (uint64 z) {
        z = SCALE; // start at 1.0
        uint64 b = base;
        uint16 e = exp;
        while (e != 0) {
            if (e & 1 != 0) z = _mul32(z, b);
            e >>= 1;
            if (e != 0) b = _mul32(b, b);
        }
    }

    function _mul32(uint64 a, uint64 b) private pure returns (uint64) {
        // (a * b) >> 32
        return uint64((uint128(a) * b) >> 32);
    }
}
