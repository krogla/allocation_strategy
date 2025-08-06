// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {PackedBytes32Helper, PackedBytes32} from "./PackedBytes32.sol";

library PackedBytes32ArrayHelper {
    using PackedBytes32Helper for PackedBytes32;

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
                res[i] = self[i].get(pos);
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
