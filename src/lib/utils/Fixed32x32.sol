// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

type Fixed32x32 is uint64;

library Fixed32x32Helper {
    uint8 internal constant DECIMALS = 32;
    uint64 internal constant SCALE = uint64(1) << DECIMALS; // 2^32 = 4,294,967,296

    error Overflow();
    error DivisionByZero();

    function wrap(uint64 value) internal pure returns (Fixed32x32) {
        return Fixed32x32.wrap(value);
    }

    function unwrap(Fixed32x32 _self) internal pure returns (uint64) {
        return Fixed32x32.unwrap(_self);
    }

    function fromUint(uint256 value) internal pure returns (Fixed32x32) {
        return Fixed32x32.wrap(uint64(_toFixed(value)));
        // return Fixed32x32.wrap(uint64(value * SCALE));
    }

    function toUint(Fixed32x32 _self) internal pure returns (uint256) {
        return _fromFixed(Fixed32x32.unwrap(_self));
        // return uint256(Fixed32x32.unwrap(_self)) >> DECIMALS;
        // return uint256(Fixed32x32.unwrap(_self)) / SCALE;
    }

    function mul(Fixed32x32 _self, uint256 value) internal pure returns (uint256) {
        uint256 rawValue = Fixed32x32.unwrap(_self);
        return _fromFixed(rawValue * value);
    }

    function _mul(Fixed32x32 _self, uint64 value) internal pure returns (Fixed32x32) {
        uint64 rawValue = Fixed32x32.unwrap(_self);
        // let Solidity handle overflow
        return Fixed32x32.wrap(rawValue * value);
    }

    function div(Fixed32x32 _self, uint256 value) internal pure returns (Fixed32x32) {
        if (value == 0) revert DivisionByZero();

        uint256 rawValue = Fixed32x32.unwrap(_self);
        uint256 result = _toFixed(rawValue) / value;

        if (result > type(uint64).max) revert Overflow();

        return Fixed32x32.wrap(uint64(result));
    }

    function _toFixed(uint256 value) private pure returns (uint256) {
        // if (value >= SCALE) revert Overflow();
        return value << DECIMALS;
        // return value * SCALE;
    }

    function _fromFixed(uint256 value) private pure returns (uint256) {
        return value >> DECIMALS;
        // return value / SCALE;
    }
}
