// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PackedUint256} from "../utils/PackedUint256.sol";
import {BitMask16} from "../utils/BitMask16.sol";

// import {console2} from "forge-std/console2.sol";

library ASCore {
    using PackedUint256 for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using BitMask16 for uint16;

    /// @dev example entity metadata
    struct EntityMetadata {
        uint256 id; // unique entity ID
        address owner; // entity owner
        string description; // entity description
    }

    /// @dev example metric metadata
    struct MetricMetadata {
        uint256 id; // unique metric ID
        address owner; // metric owner
        string description; // metric description
    }

    /// @dev example strategy metadata
    struct StrategyMetadata {
        uint256 id; // unique strategy ID
        address owner; // strategy owner
        string description; // strategy description
    }

    struct Metric {
        uint16 defaultWeight; // default weight for the metric in strategies
        MetricMetadata metadata; // metric metadata
    }

    struct Strategy {
        // todo can be reduced to Q8.8 precision?
        uint256 packedWeights; // packed weights for all metrics, 16x uint16
        uint256 sumWeights;
        uint256[16] sumX;
        StrategyMetadata metadata; // strategy metadata
    }

    struct Entity {
        uint256 packedMetricValues; //  packed params 16x uint16 in one uint256
        EntityMetadata metadata; // entity metadata
    }

    struct ASStorage {
        uint16 enabledMetricsBitMask;
        uint16 enabledStrategiesBitMask;
        mapping(uint256 => Metric) metrics; // mapping of metrics to their states
        mapping(uint256 => Strategy) strategies; // mapping of strategies to their states
        mapping(uint256 => Entity) entities; // id => Entity
        EnumerableSet.UintSet entityIds; // set of entity IDs
    }

    uint8 public constant MAX_CATEGORIES = 16;
    uint8 public constant MAX_STRATEGIES = 16;

    // resulted shares precision
    uint8 internal constant S_FRAC = 32; // Q32.32
    uint256 internal constant S_SCALE = uint256(1) << S_FRAC; // 2^32

    event UpdatedEntities(uint256 updateCount);
    event UpdatedStrategyWeights(uint256 strategyId, uint256 updatesCount);

    error NotFound();
    error NotEnabled();
    error AlreadyExists();
    error OutOfBounds();
    error LengthMismatch();
    error NoData();

    function enableStrategy(bytes32 _position, uint8 sId, string memory description) internal {
        ASStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (sMask.isBitSet(sId)) revert AlreadyExists();

        $.enabledStrategiesBitMask = sMask.setBit(sId);

        // initializing with zeros, weights should be set later
        uint256[16] memory sumX;
        $.strategies[sId] = Strategy({
            packedWeights: 0,
            sumWeights: 0,
            sumX: sumX,
            metadata: ASCore.StrategyMetadata({id: sId, description: description, owner: address(0)})
        });
    }

    function disableStrategy(bytes32 _position, uint8 sId) internal {
        ASStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled();

        // reset strategy storage
        delete $.strategies[sId];
        $.enabledStrategiesBitMask = sMask.clearBit(sId);
    }

    function enableMetric(bytes32 _position, uint8 cId, uint16 defaultWeight, string memory description)
        internal
        returns (uint256 updCnt)
    {
        ASStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledMetricsBitMask;
        if (cMask.isBitSet(cId)) revert AlreadyExists(); // skip non-enabled metrics

        $.enabledMetricsBitMask = cMask.setBit(cId);
        $.metrics[cId] = Metric({
            defaultWeight: defaultWeight,
            metadata: ASCore.MetricMetadata({id: cId, description: description, owner: address(0)})
        });

        updCnt = _setWeightsAllStrategies($, cId, defaultWeight);
    }

    function disableMetric(bytes32 _position, uint8 cId) internal returns (uint256 updCnt) {
        ASStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledMetricsBitMask;
        if (!cMask.isBitSet(cId)) revert NotEnabled(); // skip non-enabled metrics

        updCnt = _setWeightsAllStrategies($, cId, 0);

        $.enabledMetricsBitMask = cMask.clearBit(cId);
        delete $.metrics[cId];
    }

    function addEntities(bytes32 _position, uint256[] memory eIds, uint8[] memory cIds, uint16[][] memory newVals)
        internal
        returns (uint256 updCnt)
    {
        uint256 n = eIds.length;
        if (n == 0) revert NoData();

        ASStorage storage $ = _getStorage(_position);
        for (uint256 i; i < n; ++i) {
            uint256 eId = eIds[i];
            if (!$.entityIds.add(eId)) {
                revert AlreadyExists();
            }
            $.entities[eId] = Entity({
                packedMetricValues: 0,
                metadata: ASCore.EntityMetadata({id: eId, description: "", owner: address(0)})
            });
        }

        if (cIds.length > 0) {
            updCnt = _applyUpdate($, eIds, cIds, newVals);
        }
    }

    function removeEntities(bytes32 _position, uint256[] memory eIds) internal returns (uint256 updCnt) {
        uint256 n = eIds.length;
        if (n == 0) revert NotFound();

        ASStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledMetricsBitMask;
        uint8[] memory cIds = cMask.bitsToValues();
        uint256 cCnt = cIds.length;
        uint16[][] memory delVals = new uint16[][](n);

        for (uint256 i; i < n; ++i) {
            uint256 eId = eIds[i];
            if (!$.entityIds.remove(eId)) {
                revert NotFound();
            }

            uint256 slot = $.entities[eId].packedMetricValues;
            if (slot == 0) continue; // nothing to remove
            delVals[i] = new uint16[](cCnt);
            for (uint8 k = 0; k < cCnt; ++k) {
                delVals[i][k] = slot.get16(cIds[k]);
            }
        }

        updCnt = _applyUpdate($, eIds, cIds, delVals);
    }

    function setWeights(bytes32 _position, uint8 sId, uint8[] memory cIds, uint16[] memory newWeights)
        internal
        returns (uint256 updCnt)
    {
        uint256 cCnt = cIds.length;
        _checkLength(cCnt, newWeights.length);
        _checkBounds(cCnt, MAX_CATEGORIES);

        ASStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

        updCnt = _setWeights($, sId, cIds, newWeights);
    }

    function batchUpdate(
        bytes32 _position,
        uint256[] memory eIds,
        uint8[] memory cIds,
        uint16[][] memory newVals // индексы+значения per id/per cat
            // uint16[][] memory mask // 1 если k изменяем, иначе 0
    ) internal returns (uint256 updCnt) {
        ASStorage storage $ = _getStorage(_position);
        updCnt = _applyUpdate($, eIds, cIds, newVals);
    }

    function _getEntityRaw(bytes32 _position, uint256 eId) internal view returns (Entity memory) {
        return _getStorage(_position).entities[eId];
    }

    function _getStrategyRaw(bytes32 _position, uint256 sId) internal view returns (Strategy memory) {
        return _getStorage(_position).strategies[sId];
    }

    function _getMetricRaw(bytes32 _position, uint256 cId) internal view returns (Metric memory) {
        return _getStorage(_position).metrics[cId];
    }

    function getMetricValues(bytes32 _position, uint256 eId) internal view returns (uint16[] memory) {
        ASStorage storage $ = _getStorage(_position);
        _checkEntity($, eId);

        uint256 pVals = $.entities[eId].packedMetricValues;
        return pVals.unpack16();
    }

    function getWeights(bytes32 _position, uint8 sId)
        internal
        view
        returns (uint16[] memory weights, uint256 sumWeights)
    {
        ASStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

        uint256 pW = $.strategies[sId].packedWeights;
        return (pW.unpack16(), $.strategies[sId].sumWeights);
    }

    function getEnabledStrategies(bytes32 _position) internal view returns (uint8[] memory) {
        ASStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        return sMask.bitsToValues();
    }

    function getEnabledMetrics(bytes32 _position) internal view returns (uint8[] memory) {
        ASStorage storage $ = _getStorage(_position);
        uint16 cMask = $.enabledMetricsBitMask;
        return cMask.bitsToValues();
    }

    function getEntities(bytes32 _position) internal view returns (uint256[] memory) {
        ASStorage storage $ = _getStorage(_position);
        return $.entityIds.values();
    }

    function shareOf(bytes32 _position, uint256 eId, uint8 sId) internal view returns (uint256) {
        ASStorage storage $ = _getStorage(_position);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

        _checkEntity($, eId);
        return _calculateShare($, eId, sId);
    }

    function sharesOf(bytes32 _position, uint256[] memory eIds, uint8 sId) internal view returns (uint256[] memory) {
        ASStorage storage $ = _getStorage(_position);
        uint256[] memory shares = new uint256[](eIds.length);
        uint16 sMask = $.enabledStrategiesBitMask;
        if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies

        for (uint256 i = 0; i < eIds.length; i++) {
            uint256 eId = eIds[i];
            _checkEntity($, eId);
            shares[i] = _calculateShare($, eId, sId);
        }
        return shares;
    }

    // function _shareOf(ASStorage storage $, uint256 eId, uint8 sId) internal view returns (uint256) {
    //     _checkEntity($, eId);
    //     uint16 sMask = $.enabledStrategiesBitMask;
    //     if (!sMask.isBitSet(sId)) revert NotEnabled(); // skip non-enabled strategies
    //     return _calculateShare($, eId, sId);
    // }

    function _setWeightsAllStrategies(ASStorage storage $, uint8 cId, uint16 newWeight)
        private
        returns (uint256 updCnt)
    {
        uint16 sMask = $.enabledStrategiesBitMask;
        uint8[] memory cIds = new uint8[](1);
        cIds[0] = cId;
        uint16[] memory newWeights = new uint16[](1);
        newWeights[0] = newWeight;

        for (uint256 i; i < MAX_STRATEGIES; ++i) {
            if (!sMask.isBitSet(uint8(i))) continue; // skip non-enabled strategies
            updCnt += _setWeights($, uint8(i), cIds, newWeights);
        }
    }

    function _setWeights(ASStorage storage $, uint8 sId, uint8[] memory cIds, uint16[] memory newWeights)
        private
        returns (uint256 updCnt)
    {
        Strategy storage ss = $.strategies[sId];
        // get old weights/sum
        uint256 pW = ss.packedWeights;
        int256 dSum;
        uint16 cMask = $.enabledMetricsBitMask;
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
                ++updCnt;
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
        emit UpdatedStrategyWeights(sId, updCnt);
    }

    function _applyUpdate(
        ASStorage storage $,
        uint256[] memory eIds,
        uint8[] memory cIds,
        uint16[][] memory newVals // или компактнее: индексы+значения per id
            // uint16[][] memory mask // 1 если k изменяем, иначе 0
    ) private returns (uint256 updCnt) {
        uint256 n = eIds.length;
        _checkLength(newVals.length, n);

        uint256 cCnt = cIds.length;
        _checkBounds(cCnt, MAX_CATEGORIES);

        // дельты сумм по параметрам
        int256[] memory dSum = new int256[](cCnt);

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 eId = eIds[i];
                _checkEntity($, eId);
                _checkLength(newVals[i].length, cCnt);

                uint256 pVals = $.entities[eId].packedMetricValues;
                uint256 pValsNew = pVals;

                //TODO input cIds -> bitmask?
                uint16 cMask = $.enabledMetricsBitMask;
                for (uint256 k; k < cCnt; ++k) {
                    // if (mask[i][k] == 0) continue;
                    uint8 cId = cIds[k];
                    if (!cMask.isBitSet(cId)) continue; // skip non-enabled metrics

                    uint16 xOld = pValsNew.get16(cId);
                    uint16 xNew = newVals[i][k];
                    if (xNew == xOld) continue;

                    pValsNew = pValsNew.set16(cId, xNew);
                    int256 dx = int256(uint256(xNew)) - int256(uint256(xOld));
                    dSum[k] += dx;
                }

                if (pValsNew != pVals) {
                    $.entities[eId].packedMetricValues = pValsNew;
                    ++updCnt;
                }
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
        emit UpdatedEntities(updCnt);
    }

    function _calculateShare(ASStorage storage $, uint256 eId, uint8 sId) private view returns (uint256) {
        Strategy storage ss = $.strategies[sId];

        uint256 sW = ss.sumWeights;
        if (sW == 0) return 0;

        uint256 pW = ss.packedWeights;
        uint256 pVals = $.entities[eId].packedMetricValues;
        uint256 acc; // Σ_k w_k * x_{i,k} / sumX[k]

        unchecked {
            for (uint8 k; k < 16; ++k) {
                uint256 xk = pVals.get16(k);
                if (xk == 0) continue;
                uint256 sx = ss.sumX[k];
                if (sx == 0) continue;
                uint256 wk = pW.get16(k);
                //  w * x / sumX[k]
                // acc += Math.mulDiv(wk, xk, sx, Math.Rounding.Floor);
                acc += Math.mulDiv(wk, xk, sx);
            }
        }
        // return Math.mulDiv(acc, S_SCALE, sW, Math.Rounding.Floor);
        return (acc << S_FRAC) / sW; // Q32.32
    }

    function _checkEntity(ASStorage storage $, uint256 eId) private view {
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
    function _getStorage(bytes32 _position) private pure returns (ASStorage storage $) {
        assembly {
            $.slot := _position
        }
    }
}
