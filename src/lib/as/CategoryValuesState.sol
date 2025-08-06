// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {PackedBytes32} from "../utils/PackedBytes32.sol";
import {WeightsCalc} from "./WeightsCalc.sol";
import {ValueCountWeight, ValueCountWeightHelper} from "./ValueCounterWeight.sol";
import {Category, CategoryValueIndexesHelper} from "./CategoryValueIndexes.sol";
import {CategoryValuesState} from "./Types.sol";

library CategoryValuesStateHelper {
    using CategoryValueIndexesHelper for PackedBytes32;
    using ValueCountWeightHelper for ValueCountWeight;
    using WeightsCalc for *;

    error OutOfBounds();

    function _getValueCountsWeights(CategoryValuesState storage cvs)
        internal
        view
        returns (ValueCountWeight[] memory vcWeights, bool isDirty)
    {
        return (cvs.vcWeights, cvs.isDirty);
    }

    function _setValueCountsWeights(CategoryValuesState storage cvs, uint16[] memory newValues)
        internal
        returns (uint16[] memory)
    {
        // use WeightsCalc to compress the new values into ValueCountWeight array and calculate vcWeights
        (uint16[] memory idxs, ValueCountWeight[] memory vcWeights) = newValues.getValueWeights();
        // replace the existing ValueCounts array for this param type
        cvs.vcWeights = vcWeights;
        cvs.isDirty = false; // reset dirty flag after update
        return idxs;
    }

    function _recalculateValueCountsWeights(CategoryValuesState storage cvs) internal {
        if (cvs.isDirty) {
            //! warning might be too expensive
            // load all current values vcWeights
            ValueCountWeight[] memory vcWeights = cvs.vcWeights;
            // recalculate vcWeights and save
            cvs.vcWeights = vcWeights.calcWeights();
            cvs.isDirty = false;
        }
    }

    function _updateCategoryValueAndSetIndex(
        CategoryValuesState storage cvs,
        Category category,
        uint16 newValue,
        PackedBytes32 cIdxs,
        bool isNew
    ) internal returns (PackedBytes32) {
        // console.log("category=%d, new value=%d", Category.unwrap(category), newValue);
        uint16 idx;
        // find new value in existing array or add it
        // console.log("isNew=%s", isNew ? "true" : "false");
        idx = isNew ? 0 : cIdxs.getIdx(category);
        // console.log("old idx=%d", idx);
        idx = _updateValueCounts(cvs, idx, newValue, isNew);
        // console.log("updated idx=%d", idx);

        // update entity's category index
        return cIdxs.setIdx(category, idx);
    }

    function _updateValueCounts(CategoryValuesState storage cvs, uint16 idx, uint16 value, bool isNew)
        internal
        returns (uint16)
    {
        (uint16 newIdx, bool isDirty) = __updateValueCounts(cvs.vcWeights, idx, value, isNew);
        if (isDirty) {
            // mark as dirty if value was changed
            // console.log("marking as dirty");
            cvs.isDirty = true;
        }
        return newIdx;
    }

    /// @notice decrease count for existing parameter value and find or add new value and increase count
    /// @param vcWeights value-counts storage
    /// @param idx Index of the old value (1-based)
    /// @param value Parameter value to find or add
    /// @return newIdx Index of the value in the array (1-based)
    /// @return isDirty Whether the value was changed
    function __updateValueCounts(ValueCountWeight[] storage vcWeights, uint16 idx, uint16 value, bool isNew)
        private
        returns (uint16 newIdx, bool isDirty)
    {
        WeightsCalc.checkMaxValue(value); // ensure value is in range 0..10_000
        uint256 length = vcWeights.length;
        // console.log("Updating value counts, current length=%d, idx=%d, value=%d", length, idx, value);
        uint16 v;
        uint16 c;
        isDirty = true; // assume we will change something

        if (!isNew) {
            if (idx >= length) {
                // console.log("idx out of bounds, length=%d, idx=%d", length, idx);
                revert OutOfBounds();
            }

            (v, c) = vcWeights[idx].unpackVC();
            if (value == v) {
                // console.log("value unchanged");
                return (idx, false); // no need to change anything, value the same as old one
            }
            // quick check if the current value is last one (in array), so we can reuse its index
            if (c == 1) {
                // update storage just with new value
                // console.log("updating storage just with new value, same idx =%d", idx);
                vcWeights[idx] = ValueCountWeightHelper.packVC(value, c);
                return (idx, isDirty);
            }
            // otherwise decrease count for old value (ensure consistency thanks to overflow check)
            // and update storage
            vcWeights[idx] = ValueCountWeightHelper.packVC(v, --c);
            // console.log("decreased count for old value=%d, new count=%d", v, c);
        }

        uint16 zIdx = 0;
        // first, try to find existing value
        for (uint256 i = 0; i < length; ++i) {
            if (isNew && i == idx) {
                // console.log("skipping old value index=%d", i);
                continue; // skip the old value index
            }
            (v, c) = vcWeights[i].unpackVC();
            if (v == value) {
                // console.log("Found existing value=%d at index=%d, incrementing count", value, i);
                // Found existing value, increment count
                vcWeights[i] = ValueCountWeightHelper.packVC(value, ++c);
                return (uint16(i), isDirty);
            } else if (c == 0 && zIdx == 0) {
                // remember first zero count index
                zIdx = uint16(i + 1); // store as 1-based index
                    // console.log("Found empty slot at index=%d", zIdx);
            }
        }

        if (zIdx > 0) {
            unchecked {
                --zIdx; // switch to 0-based index
            }
            // console.log("Reusing empty slot at index=%d for new value=%d", zIdx, value);
            // Found a slot with count = 0, reuse it
            vcWeights[zIdx] = ValueCountWeightHelper.packVC(value, 1);
            return (zIdx, isDirty);
        }

        // console.log("No existing value and no empty slots, adding new value=%d at index=%d", value, length);
        // No existing value and no empty slots, add new entry
        vcWeights.push(ValueCountWeightHelper.packVC(value, 1));
        return (uint16(length), isDirty);
    }
}
