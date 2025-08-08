// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

library FixedBase {
    function fromUint(uint256 v, uint8 decimalBits) internal pure returns (uint256) {
        return uint256(_toFixed(v, decimalBits));
    }

    function toUint(uint256 x, uint8 decimalBits) internal pure returns (uint256) {
        return _fromFixed(x, decimalBits);
    }

    function mulN(uint256 x, uint256 v, uint8 decimalBits) internal pure returns (uint256) {
        return _fromFixed(uint256(x) * v, decimalBits);
    }

    function divN(uint256 x, uint256 v, uint8 decimalBits) internal pure returns (uint256) {
        uint256 result = _toFixed(x, decimalBits) / v;

        return uint256(result);
    }

    function _toFixed(uint256 v, uint8 decimalBits) private pure returns (uint256) {
        return v << decimalBits;
    }

    function _fromFixed(uint256 v, uint8 decimalBits) private pure returns (uint256) {
        return v >> decimalBits;
    }
}
