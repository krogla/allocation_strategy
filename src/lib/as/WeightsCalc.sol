// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixed32x32Helper, Fixed32x32} from "../utils/Fixed32x32.sol";
import {ValueCountWeightHelper, ValueCountWeight, ValueCountWeightStruct} from "./ValueCounterWeight.sol";

/// @title WeightsCalc Library
/// @notice Provides a library for calculating weights based on values statistics
/// @dev Supports exponential and linear distributions, uses compressed values arrays into ValueCountWeight structures
/// @dev Uses 32.32 fixed-point arithmetic for coefficients, ensuring precision in calculations
/// @dev Based on the following constraints:
///      1. Parameter values must be within range 0 to 10_000 (inclusive)
///      2. Array length must not exceed 65_536 elements (allowing uint16 for values and indices)
///      Note: In practice, the number of elements should be limited to a smaller number (e.g. 1000)
///      to maintain reasonable gas consumption.
library WeightsCalc {
    using ValueCountWeightHelper for *;
    using Fixed32x32Helper for Fixed32x32;

    uint16 internal constant MAX_VALUE = 10_000; // i.e. 0…10_000 inclusive
    uint16 internal constant MAX_COUNT = 1_000; // max number of the input items

    error MaxCountExceeded();
    error MaxValueExceeded();

    function checkMaxCount(uint256 c) internal pure {
        if (c > MAX_COUNT) revert MaxCountExceeded();
    }

    function checkMaxValue(uint256 v) internal pure {
        if (v > MAX_VALUE) revert MaxValueExceeded();
    }

    function toStructs(ValueCountWeight[] memory vcWeights) internal pure returns (ValueCountWeightStruct[] memory) {
        ValueCountWeightStruct[] memory structs = new ValueCountWeightStruct[](vcWeights.length);
        for (uint256 i = 0; i < vcWeights.length; i++) {
            structs[i] = vcWeights[i].toStruct();
        }
        return structs;
    }

    function fromStructs(ValueCountWeightStruct[] memory structs) internal pure returns (ValueCountWeight[] memory) {
        ValueCountWeight[] memory vcWeights = new ValueCountWeight[](structs.length);
        for (uint256 i = 0; i < structs.length; i++) {
            vcWeights[i] = structs[i].fromStruct();
        }
        return vcWeights;
    }

    /// @notice Calculate linear weights based on vals
    /// @dev Compresses input vals using compressValues and calculates linear weights
    /// @param vals Array of uint16 vals to process
    /// @return idxs Array of reference indices
    /// @return vcWeights Compressed vals array with calculated linear weights
    function getValueWeights(uint16[] memory vals)
        internal
        pure
        returns (uint16[] memory idxs, ValueCountWeight[] memory vcWeights)
    {
        (idxs, vcWeights) = compressValues(vals);
        calcWeights(vcWeights);
    }

    /// @notice Calculate exponential weights based on vals and decay rate
    /// @dev Compresses input vals using compressValues and calculates exponential weights
    /// @param vals Array of uint16 vals to process
    /// @param r Decay rate as Fixed32x32
    /// @return idxs Array of reference indices
    /// @return vcWeights Compressed vals array with calculated exponential weights
    function getValueWeightsExp(uint16[] memory vals, Fixed32x32 r)
        internal
        pure
        returns (uint16[] memory idxs, ValueCountWeight[] memory vcWeights)
    {
        (idxs, vcWeights) = compressValues(vals);
        calcWeightsExp(vcWeights, r);
    }

    /// @notice proportional direct distribution
    /// @dev v ↑ => wight ↑ ; 0 → 0
    function calcWeights(ValueCountWeight[] memory vcWeights) internal pure returns (ValueCountWeight[] memory) {
        _calcWeights(vcWeights, Fixed32x32.wrap(0), _calcWeightLinear);
        return vcWeights;
    }

    /// @notice exponential distribution
    /// @dev r > 1: v ↑ => wight exp(↑) ; 0 → 0
    /// @dev r < 1: v ↑ => wight exp(↓) ; 0 → 0
    /// @param vcWeights array of v statistics, i.e. v and count pairs
    /// @param r 32.32 fixed-point number, used for exponential weight calculation,

    // Value weight: w(v)=r^v, where r=A^k
    // `k≈0` - almost linear function, `k≫0` — clearly exponential
    // `A` - base of the exponent
    // e.g. almost linear: A=2, k=1e-4 => r = 2^0.0001 ≈ 1.000069 or pre-computed 32.32: uint64 r = 4294970000;
    function calcWeightsExp(ValueCountWeight[] memory vcWeights, Fixed32x32 r)
        internal
        pure
        returns (ValueCountWeight[] memory)
    {
        _calcWeights(vcWeights, r, _calcWeightExp);
        return vcWeights;
    }

    /// TODO?
    /// @notice proportional inverse distribution
    /// @dev v ↑ => wight ↓ ; 0 → 0
    // function weightsInverse(ValueCountWeight[] memory vcWeights) internal pure returns (ValueCountWeight[] memory) {
    //        return _calcWeights(vcWeights, 0, _calcWeightInverse);
    // }

    /// @dev compresses uint16[] into ValueCountWeight[] with v and count
    /// @notice vals are 0…10_000 inclusive; count is how many times v appears in the array
    function compressValues(uint16[] memory vals)
        internal
        pure
        returns (uint16[] memory idxs, ValueCountWeight[] memory vcWeights)
    {
        // first pass: count frequencies
        uint256 cnt = vals.length;
        // ensure we do not exceed the items count limit
        checkMaxCount(cnt);

        // in 1st loop we use freqMap to filling unique value's counts,
        // as unique value count will not exceed input array length, so it fits into uint16
        uint16[MAX_VALUE + 1] memory freqMap; // 0…10_000 inclusive
        uint16 uniq;

        unchecked {
            for (uint256 i; i < cnt; ++i) {
                uint16 v = vals[i];
                // guarantee that value are in range 0..10_000
                checkMaxValue(v);
                uint16 c = freqMap[v];
                uniq += (c == 0 ? 1 : 0);
                freqMap[v] = c + 1;
            }
        }

        // second pass: collect resulting pairs
        vcWeights = new ValueCountWeight[](uniq);
        uint16 j;

        unchecked {
            for (uint16 v = 0; v <= MAX_VALUE; ++v) {
                uint16 c = freqMap[v];
                if (c != 0) {
                    vcWeights[j] = ValueCountWeightHelper.packVC(v, c);
                    /// @dev overwrite freqMap[v] with index j, i.e. save position of the unique value in vcWeights
                    freqMap[v] = j;
                    if (++j == uniq) break; // all unique vals are collected
                }
            }
        }

        /* fill indexes */
        idxs = new uint16[](cnt);
        unchecked {
            for (uint256 i; i < cnt; ++i) {
                // exists guaranteed, as we checked it in the previous loop
                idxs[i] = freqMap[vals[i]];
            }
        }
    }

    // weight calculation functions
    /// @dev calculates coefficients for given v statistics
    /// @param vcWeights array of v statistics, i.e. v and count pairs
    /// @param r 32.32 fixed-point number, used for exponential weight calculation,
    function _calcWeights(
        ValueCountWeight[] memory vcWeights,
        Fixed32x32 r,
        function(uint16, uint64) internal pure returns (uint64) __calcRawWeight
    ) internal pure returns (ValueCountWeight[] memory) {
        uint256 cnt = vcWeights.length;
        if (cnt == 0) return vcWeights;

        uint128 total;
        unchecked {
            for (uint256 i; i < cnt; ++i) {
                ValueCountWeight vcWeight = vcWeights[i];
                (uint16 v, uint16 c) = vcWeight.unpackVC();
                uint64 w = __calcRawWeight(v, Fixed32x32.unwrap(r));
                if (w > 0) {
                    total += w * c;
                }
                // save raw weight
                vcWeights[i] = vcWeight.setW(Fixed32x32.wrap(w));
            }
        }
        if (total == 0) return vcWeights;

        // normalize to 1.0
        unchecked {
            for (uint256 i; i < cnt; ++i) {
                ValueCountWeight vcWeight = vcWeights[i];
                vcWeights[i] = vcWeight.setW(vcWeight.getW().div(total)); // always ≤ 1.0
            }
        }
        return vcWeights;
    }

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
        z = Fixed32x32Helper.SCALE; // start at 1.0
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
