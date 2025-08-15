// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

library ASConvertor {
    uint16 constant FEE_MIN = 0; // bps
    uint16 constant FEE_MAX = 500; // bps
    uint16 constant FEE_MIN_WEIGHT = 5000; //bps
    uint16 constant FEE_MAX_WEIGHT = 25000; //bps

    uint16 constant TECH_DVT = 1;
    uint16 constant TECH_VANILLA = 0;
    uint16 constant TECH_DVT_WEIGHT = 15000; //bps
    uint16 constant TECH_VANILLA_WEIGHT = 10000; //bps

    uint16 constant PERF_GOOD = 9500; //bps
    uint16 constant PERF_LOW = 8500; //bps
    uint16 constant PERF_BAD = 7000; //bps
    uint16 constant PERF_GOOD_WEIGHT = 10000; //bps
    uint16 constant PERF_LOW_WEIGHT = 8000; //bps
    uint16 constant PERF_BAD_WEIGHT = 3000; //bps

    error BPSOverflow();

    function _rescaleBps(uint16[] memory vals) internal pure returns (uint16[] memory) {
        uint256 n = vals.length;
        uint256 totalDefined;
        uint256 undefinedCount;

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 v = vals[i];
                if (v == 10000) {
                    ++undefinedCount;
                } else {
                    totalDefined += v;
                }
            }
        }

        if (totalDefined > 10000) {
            revert BPSOverflow();
        }

        if (undefinedCount == 0) {
            return vals;
        }

        uint256 remaining;
        unchecked {
            remaining = 10000 - totalDefined;
        }
        uint256 share = remaining / undefinedCount;
        uint256 remainder = remaining % undefinedCount;

        unchecked {
            for (uint256 i; i < n && undefinedCount > 0; ++i) {
                uint256 v = vals[i];
                if (v == 10000) {
                    v = share;
                    if (remainder > 0) {
                        ++v;
                        --remainder;
                    }
                    vals[i] = uint16(v);
                    --undefinedCount;
                }
            }
        }
        return vals;
    }

    function _convertFee(uint16 v) internal pure returns (uint16) {
        return uint16(
            uint256(v - FEE_MIN) * uint256(FEE_MAX_WEIGHT - FEE_MIN_WEIGHT) / uint256(FEE_MAX - FEE_MIN)
                + FEE_MIN_WEIGHT
        );
    }

    function _unConvertFee(uint16 w) internal pure returns (uint16) {
        return uint16((uint256(w) - FEE_MIN_WEIGHT) * (FEE_MAX - FEE_MIN) / (FEE_MAX_WEIGHT - FEE_MIN_WEIGHT) + FEE_MIN);
    }

    function _convertTech(uint16 v) internal pure returns (uint16) {
        return v == TECH_DVT ? TECH_DVT_WEIGHT : TECH_VANILLA_WEIGHT;
    }

    function _unConvertTech(uint16 w) internal pure returns (uint16) {
        return w == TECH_DVT_WEIGHT ? TECH_DVT : TECH_VANILLA;
    }

    function _convertPerf(uint16 v) internal pure returns (uint16) {
        return v >= PERF_GOOD ? PERF_GOOD_WEIGHT : v >= PERF_LOW ? PERF_LOW_WEIGHT : PERF_BAD_WEIGHT;
    }

    function _unConvertPerf(uint16 w) internal pure returns (uint16) {
        return w >= PERF_GOOD_WEIGHT ? PERF_GOOD : w >= PERF_LOW_WEIGHT ? PERF_LOW : PERF_BAD;
    }

    function _convertFees(uint16[] memory vals) internal pure returns (uint16[] memory) {
        for (uint256 i = 0; i < vals.length; i++) {
            vals[i] = _convertFee(vals[i]);
        }
        return vals;
    }

    function _convertTechs(uint16[] memory techs) internal pure returns (uint16[] memory) {
        for (uint256 i = 0; i < techs.length; i++) {
            techs[i] = _convertTech(techs[i]);
        }
        return techs;
    }

    function _convertPerfs(uint16[] memory perfs) internal pure returns (uint16[] memory) {
        for (uint256 i = 0; i < perfs.length; i++) {
            perfs[i] = _convertPerf(perfs[i]);
        }
        return perfs;
    }
}
