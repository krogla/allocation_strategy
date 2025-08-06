// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {PackedBytes32, PackedBytes32Helper} from "../utils/PackedBytes32.sol";
import {Category} from "./Types.sol";

library CategoryValueIndexesHelper {
    using PackedBytes32Helper for PackedBytes32;

    function getIdx(PackedBytes32 _self, Category _category) internal pure returns (uint16 idx) {
        return _self.get(Category.unwrap(_category));
    }

    function setIdx(PackedBytes32 _self, Category _category, uint16 idx) internal pure returns (PackedBytes32) {
        return _self.set(Category.unwrap(_category), idx);
    }
}
