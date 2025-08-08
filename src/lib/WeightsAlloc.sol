// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

// import {console2} from "forge-std/console2.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PackedUint256} from "./utils/PackedUint256.sol";
import {BitMask16} from "./utils/BitMask16.sol";

library WeightsAlloc {
    using PackedUint256 for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using BitMask16 for uint16;

    struct EntityMetadata {
        uint32 id; // unique entity ID
        address owner; // entity owner
        string description; // entity description
    }

    struct CategoryMetadata {
        uint8 id; // unique category ID
        address owner; // category owner
        string description; // category description
    }

    struct StrategyMetadata {
        uint8 id; // unique strategy ID
        address owner; // strategy owner
        string description; // strategy description
    }

    struct Category {
        uint16 defaultWeight; // default weight for the category in strategies
        CategoryMetadata metadata; // category metadata
    }

    struct Strategy {
        // todo can be reduced to Q8.8 precision?
        uint256 packedWeights; // packed weights for all categories, 16x uint16
        uint256 sumWeights;
        uint256[16] sumX;
        StrategyMetadata metadata; // strategy metadata
    }

    struct Entity {
        uint256 packedCategoryValues; //  packed params 16x uint16 in one uint256
        EntityMetadata metadata; // entity metadata
    }

    struct WAStorage {
        uint16 enabledCategoriesBitMask;
        uint16 enabledStrategiesBitMask;
        mapping(uint256 => Category) categories; // mapping of categories to their states
        mapping(uint256 => Strategy) strategies; // mapping of strategies to their states
        mapping(uint256 => Entity) entities; // id => Entity
        EnumerableSet.UintSet entityIds; // set of entity IDs
    }

    uint8 constant MAX_CATEGORIES = 16;
    uint8 constant MAX_STRATEGIES = 16;

    // resulted shares precision
    uint8 internal constant S_FRAC = 32; // Q32.32
    uint256 internal constant S_SCALE = 1 << S_FRAC; // 2^32

    error NotFound();
    error NotEnabled();
    error AlreadyExists();
    error OutOfBounds();
    error LengthMismatch();

    function enableStrategy(bytes32 _position, uint8 sId, StrategyMetadata memory metadata) internal {
        WAStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (sMask.isBitSet(sId)) revert AlreadyExists();

        $.enabledStrategiesBitMask = sMask.setBit(sId);

        // initializing with zeros, weights should be set later
        uint256[16] memory sumX;
        $.strategies[sId] = Strategy({packedWeights: 0, sumWeights: 0, sumX: sumX, metadata: metadata});
    }

    function disableStrategy(bytes32 _position, uint8 sId) internal {
        WAStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled();

        // reset strategy storage
        delete $.strategies[sId];
        $.enabledStrategiesBitMask = sMask.clearBit(sId);
    }

    function enableCategory(bytes32 _position, uint8 cId, uint16 defaultWeight, CategoryMetadata memory metadata)
        internal
    {
        WAStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledCategoriesBitMask;
        if (cMask.isBitSet(cId)) revert AlreadyExists(); // skip non-enabled categories

        $.enabledCategoriesBitMask = cMask.setBit(cId);
        $.categories[cId] = Category({defaultWeight: defaultWeight, metadata: metadata});

        _setWeightsAllStrategies($, cId, defaultWeight);
    }

    function disableCategory(bytes32 _position, uint8 cId) internal {
        WAStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledCategoriesBitMask;
        if (!cMask.isBitSet(cId)) revert NotEnabled(); // skip non-enabled categories

        _setWeightsAllStrategies($, cId, 0);

        $.enabledCategoriesBitMask = cMask.clearBit(cId);
        delete $.categories[cId];
    }

    function addEntities(bytes32 _position, uint32[] memory eIds, uint8[] memory cIds, uint16[][] memory newVals)
        internal
    {
        uint256 n = eIds.length;
        if (n == 0) revert NotFound();

        WAStorage storage $ = _getStorage(_position);
        for (uint256 i; i < n; ++i) {
            uint32 eId = eIds[i];
            if (!$.entityIds.add(eId)) {
                revert AlreadyExists();
            }
        }

        _applyUpdate($, eIds, cIds, newVals);
    }

    function removeEntities(bytes32 _position, uint32[] memory eIds) internal {
        uint256 n = eIds.length;
        if (n == 0) revert NotFound();

        WAStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledCategoriesBitMask;
        uint8[] memory cIds = cMask.bitsToValues();
        uint256 cCnt = cIds.length;
        uint16[][] memory delVals = new uint16[][](n);

        for (uint256 i; i < n; ++i) {
            uint32 eId = eIds[i];
            if (!$.entityIds.remove(eId)) {
                revert NotFound();
            }

            uint256 slot = $.entities[eId].packedCategoryValues;
            if (slot == 0) continue; // nothing to remove
            delVals[i] = new uint16[](cCnt);
            for (uint8 k = 0; k < cCnt; ++k) {
                delVals[i][k] = slot.get16(cIds[k]);
            }
        }

        _applyUpdate($, eIds, cIds, delVals);
    }

    function setWeights(bytes32 _position, uint8 sId, uint8[] memory cIds, uint16[] memory newWeights) internal {
        uint256 cCnt = cIds.length;
        _checkLength(cCnt, newWeights.length);
        _checkBounds(cCnt, MAX_CATEGORIES);

        WAStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

        _setWeights($, sId, cIds, newWeights);
    }

    function batchUpdate(
        bytes32 _position,
        uint32[] memory eIds,
        uint8[] memory cIds,
        uint16[][] memory newVals // или компактнее: индексы+значения per id
            // uint16[][] memory mask // 1 если k изменяем, иначе 0
    ) internal {
        WAStorage storage $ = _getStorage(_position);
        _applyUpdate($, eIds, cIds, newVals);
    }

    function _getEntityRaw(bytes32 _position, uint32 eId) internal view returns (Entity memory) {
        return _getStorage(_position).entities[eId];
    }

    function _getStrategyRaw(bytes32 _position, uint8 sId) internal view returns (Strategy memory) {
        return _getStorage(_position).strategies[sId];
    }

    function _getCategoryRaw(bytes32 _position, uint8 cId) internal view returns (Category memory) {
        return _getStorage(_position).categories[cId];
    }

    function getCategoryValues(bytes32 _position, uint32 eId) internal view returns (uint16[] memory) {
        WAStorage storage $ = _getStorage(_position);
        _checkEntity($, eId);

        uint256 pCV = $.entities[eId].packedCategoryValues;
        return pCV.unpack16();
    }

    function getWeights(bytes32 _position, uint8 sId)
        internal
        view
        returns (uint16[] memory weights, uint256 sumWeights)
    {
        WAStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

        uint256 pW = $.strategies[sId].packedWeights;
        return (pW.unpack16(), $.strategies[sId].sumWeights);
    }

    function getEnabledStrategies(bytes32 _position) internal view returns (uint8[] memory) {
        WAStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        return sMask.bitsToValues();
    }

    function getEnabledCategories(bytes32 _position) internal view returns (uint8[] memory) {
        WAStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledCategoriesBitMask;
        return cMask.bitsToValues();
    }

    function shareOf(bytes32 _position, uint32 eId, uint8 sId) internal view returns (uint256) {
        WAStorage storage $ = _getStorage(_position);
        _checkEntity($, eId);

        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

        return _calculateShare($, eId, sId);
    }

    function sharesOf(bytes32 _position, uint32[] memory eIds, uint8 sId) internal view returns (uint256[] memory) {
        WAStorage storage $ = _getStorage(_position);
        uint256[] memory shares = new uint256[](eIds.length);

        for (uint256 i = 0; i < eIds.length; i++) {
            uint32 eId = eIds[i];
            _checkEntity($, eId);

            uint16 sMask = $.enabledStrategiesBitMask;
            if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

            shares[i] = _calculateShare($, eId, sId);
        }
        return shares;
    }

    function _setWeightsAllStrategies(WAStorage storage $, uint8 cId, uint16 newWeight) private {
        uint16 sMask = $.enabledStrategiesBitMask;
        uint8[] memory cIds = new uint8[](1);
        cIds[0] = cId;
        uint16[] memory newWeights = new uint16[](1);
        newWeights[0] = newWeight;

        for (uint256 i; i < MAX_STRATEGIES; ++i) {
            if (!sMask.isBitSet(uint8(i))) continue; // skip non-enabled strategies
            _setWeights($, uint8(i), cIds, newWeights);
        }
    }

    function _setWeights(WAStorage storage $, uint8 sId, uint8[] memory cIds, uint16[] memory newWeights) private {
        Strategy storage ss = $.strategies[sId];
        // get old weights/sum
        uint256 pW = ss.packedWeights;
        int256 dSum;
        uint16 cMask = $.enabledCategoriesBitMask;
        unchecked {
            for (uint8 k; k < cIds.length; ++k) {
                uint8 cId = cIds[k];
                if (!cMask.isBitSet(cId)) continue;

                uint16 oldW = pW.get16(cId);
                uint16 newW = newWeights[k];
                if (newW == oldW) continue;

                int256 dx = int256(uint256(newW)) - int256(uint256(oldW));
                dSum += dx;
                // update local packedWeights
                pW = pW.set16(cId, newW);
            }
        }

        // apply delta to sumWeights
        uint256 sW = ss.sumWeights;
        if (dSum != 0) {
            if (dSum > 0) sW += uint256(dSum);
            else sW -= uint256(-dSum);
        }
        ss.packedWeights = pW;
        ss.sumWeights = sW;
    }

    function _applyUpdate(
        WAStorage storage $,
        uint32[] memory eIds,
        uint8[] memory cIds,
        uint16[][] memory newVals // или компактнее: индексы+значения per id
            // uint16[][] memory mask // 1 если k изменяем, иначе 0
    ) private {
        uint256 n = eIds.length;
        _checkLength(newVals.length, n);

        uint256 cCnt = cIds.length;
        _checkBounds(cCnt, MAX_CATEGORIES);

        // дельты сумм по параметрам
        int256[] memory dSum = new int256[](cCnt);
        unchecked {
            for (uint256 i; i < n; ++i) {
                uint32 eId = eIds[i];
                _checkEntity($, eId);
                _checkLength(newVals[i].length, cCnt);

                uint256 pCV = $.entities[eId].packedCategoryValues;
                uint256 pCVNew = pCV;

                //TODO input cIds -> bitmask?
                uint16 cMask = $.enabledCategoriesBitMask;
                for (uint256 k; k < cCnt; ++k) {
                    // if (mask[i][k] == 0) continue;
                    uint8 cId = cIds[k];
                    if (!cMask.isBitSet(cId)) continue; // skip non-enabled categories

                    uint16 xOld = pCV.get16(cId);
                    uint16 xNew = newVals[i][k];
                    if (xNew == xOld) continue;

                    pCVNew = pCVNew.set16(cId, xNew);
                    int256 dx = int256(uint256(xNew)) - int256(uint256(xOld));
                    dSum[k] += dx;
                }
                if (pCVNew != pCV) $.entities[eId].packedCategoryValues = pCVNew;
            }
        }

        uint16 sMask = $.enabledStrategiesBitMask;
        for (uint256 i; i < MAX_STRATEGIES; ++i) {
            if (!sMask.isBitSet(uint8(i))) continue; // skip non-enabled strategies
            Strategy storage ss = $.strategies[i];
            // update sumX[k]
            for (uint256 k; k < cCnt; ++k) {
                int256 dx = dSum[k];
                if (dx == 0) continue;
                uint8 cId = cIds[k];
                if (dx > 0) ss.sumX[cId] += uint256(dx);
                else ss.sumX[cId] -= uint256(-dx); // no overflow, due to dx = Σ(new-old)
            }
        }
    }

    function _calculateShare(WAStorage storage $, uint32 eId, uint8 sId) private view returns (uint256) {
        Strategy storage ss = $.strategies[sId];

        uint256 sW = ss.sumWeights;
        if (sW == 0) return 0;

        uint256 pW = ss.packedWeights;
        uint256 pCV = $.entities[eId].packedCategoryValues;
        uint256 acc; // Σ_k w_k * x_{i,k} / sumX[k]

        unchecked {
            for (uint8 k; k < 16; ++k) {
                uint256 xk = pCV.get16(k);
                if (xk == 0) continue;
                uint256 sx = ss.sumX[k];
                if (sx == 0) continue;
                uint256 wk = pW.get16(k);
                //  w * x / sumX[k]
                acc += Math.mulDiv(wk, xk, sx);
            }
        }
        // return Math.mulDiv(acc, S_SCALE, sW);
        return (acc << S_FRAC) / sW; // Q32.32
    }

    function _checkEntity(WAStorage storage $, uint32 eId) private view {
        if (!$.entityIds.contains(eId)) {
            revert NotFound();
        }
    }

    function _checkIdBounds(uint256 value, uint256 max) private pure {
        if (value >= max) {
            revert OutOfBounds();
        }
    }

    function _checkBounds(uint256 value, uint256 max) private pure {
        if (value > max) {
            revert OutOfBounds();
        }
    }

    function _checkLength(uint256 l1, uint256 l2) private pure {
        if (l1 != l2) {
            revert LengthMismatch();
        }
    }

    /// @dev Returns the storage slot for the given position.
    function _getStorage(bytes32 _position) private pure returns (WAStorage storage $) {
        assembly {
            $.slot := _position
        }
    }
}
