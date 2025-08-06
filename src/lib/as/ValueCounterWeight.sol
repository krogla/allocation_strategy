// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixed32x32} from "../utils/Fixed32x32.sol";
import {ValueCountWeight, ValueCountWeightStruct} from "./Types.sol";

library ValueCountWeightHelper {
    function fromStruct(ValueCountWeightStruct memory _self) internal pure returns (ValueCountWeight) {
        return pack(_self.value, _self.count, _self.weight);
    }

    function toStruct(ValueCountWeight _self) internal pure returns (ValueCountWeightStruct memory) {
        (uint16 value, uint16 count, Fixed32x32 weight) = unpack(_self);
        return ValueCountWeightStruct(value, count, weight);
    }

    /**
     * @dev pack the components into a ValueCountWeight object.
     */
    function pack(uint16 value, uint16 count, Fixed32x32 weight) internal pure returns (ValueCountWeight) {
        return ValueCountWeight.wrap((uint96(value) << 80) | uint96(count) << 64 | uint96(Fixed32x32.unwrap(weight)));
    }

    /**
     * @dev Split a ValueCountWeight into its components.
     */
    function unpack(ValueCountWeight _self) internal pure returns (uint16 value, uint16 count, Fixed32x32 weight) {
        uint96 raw = ValueCountWeight.unwrap(_self);

        weight = Fixed32x32.wrap(uint64(raw));
        count = uint16(raw >> 64);
        value = uint16(raw >> 80);
        return (value, count, weight);
    }

    /**
     * @dev quick pack without weight
     */
    function packVC(uint16 value, uint16 count) internal pure returns (ValueCountWeight) {
        return ValueCountWeight.wrap((uint96(value) << 80) | uint96(count) << 64);
    }

    function unpackVC(ValueCountWeight _self) internal pure returns (uint16 value, uint16 count) {
        uint96 raw = ValueCountWeight.unwrap(_self);

        count = uint16(raw >> 64);
        value = uint16(raw >> 80);
        return (value, count);
    }

    function setW(ValueCountWeight _self, Fixed32x32 weight) internal pure returns (ValueCountWeight) {
        uint96 raw = ValueCountWeight.unwrap(_self);
        // keep the higher bits and set the weight
        return ValueCountWeight.wrap(raw & (~uint96(0) << 64) | uint96(Fixed32x32.unwrap(weight)));
    }

    function getW(ValueCountWeight _self) internal pure returns (Fixed32x32) {
        // just shrink the higher bits
        return Fixed32x32.wrap(uint64(ValueCountWeight.unwrap(_self)));
    }

    function setC(ValueCountWeight _self, uint16 count) internal pure returns (ValueCountWeight) {
        uint96 raw = ValueCountWeight.unwrap(_self);
        // nullify count bits and keep the rest
        return ValueCountWeight.wrap(raw & (~(uint96(~uint16(0)) << 64)) | uint96(count) << 64);
    }
}
