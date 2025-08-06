// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {PackedBytes32} from "../utils/PackedBytes32.sol";
import {Category, CategoryValueIndexesHelper} from "./CategoryValueIndexes.sol";
import {AllocationStrategyStorage, Config, CategoryValuesState, Entity, Strategy, StrategyState} from "./Types.sol";

library AllocationStrategyStorageHelper {
    using AllocationStrategyStorageHelper for AllocationStrategyStorage;
    using CategoryValueIndexesHelper for PackedBytes32;

    error LengthMismatch();
    error OutOfBounds();

    /// todo add param type
    /// todo add param value
    /// todo del param type
    /// todo del param value
    /// todo change param value
    /// todo

    // function getParamTypeValueByIdx(bytes32 _position, Category _category, uint16 _idx)
    //     internal
    //     view
    //     returns (ValueCount)
    // {
    //     return getParamValuesStorage(_position, _category)[_idx];
    // }

    // function getParamValuesStorage(bytes32 _position, Category _category)
    //     internal
    //     view
    //     returns (ValueCount[] storage)
    // {
    //     return _getStorage(_position)._paramValues[_category];
    // }

    function getCategoryValuesState(AllocationStrategyStorage storage $, Category _category)
        internal
        view
        returns (CategoryValuesState storage)
    {
        return $._categoryStates[_category];
    }

    function getStrategyState(AllocationStrategyStorage storage $, Strategy _strategy)
        internal
        view
        returns (StrategyState storage)
    {
        return $._strategyStates[_strategy];
    }

    function getConfigStorage(AllocationStrategyStorage storage $) internal view returns (Config storage) {
        return $._config;
    }

    function getEntitiesStorage(AllocationStrategyStorage storage $) internal view returns (Entity[] storage) {
        return $._entities;
    }

    // function getEntity(AllocationStrategyStorage storage $, uint32 _entityId) internal view returns (Entity memory) {
    //     return getEntitiesStorage($)[_entityId];
    // }

    function getEntityCategoryValueIndexesStorage(AllocationStrategyStorage storage $)
        internal
        view
        returns (PackedBytes32[] storage)
    {
        return $._entityCategoryValueIndexes;
    }

    function setEntityCategoryValueIndexesStorage(AllocationStrategyStorage storage $, PackedBytes32[] memory _newIndexes)
        internal
    {
        // PackedBytes32[] storage entityCategoryIdxs = $.getEntityCategoryValueIndexesStorage();
        if (_newIndexes.length != $._entityCategoryValueIndexes.length) {
            revert LengthMismatch();
        }
        $._entityCategoryValueIndexes = _newIndexes;
    }

    function getEntityCategoryIdxs(AllocationStrategyStorage storage $, uint32 _entityId)
        internal
        view
        returns (PackedBytes32)
    {
        return $._entityCategoryValueIndexes[_entityId];
    }

    function setEntityCategoryIdxs(AllocationStrategyStorage storage $, uint32 _entityId, PackedBytes32 _cIdxs)
        internal
    {
        $._entityCategoryValueIndexes[_entityId] = _cIdxs;
    }

    // function getEntityCategoryIdx(AllocationStrategyStorage storage $, uint32 _entityId, Category _category)
    //     internal
    //     view
    //     returns (uint16 _idx)
    // {
    //     PackedBytes32 vIdxs = $.getEntityCategoryIdxs(_entityId);
    //     _idx = vIdxs.getIdx(_category);
    // }

    // function setEntityCategoryIdx(
    //     AllocationStrategyStorage storage $,
    //     uint32 _entityId,
    //     Category _category,
    //     uint16 _newIdx
    // ) internal {
    //     PackedBytes32 vIdxs = $.getEntityCategoryIdxs(_entityId);
    //     $.setEntityCategoryIdxs(_entityId, vIdxs.setIdx(_category, _newIdx));
    // }

    function getAllocationStrategyStorage(bytes32 _position)
        internal
        pure
        returns (AllocationStrategyStorage storage)
    {
        return _getStorage(_position);
    }

    function _getStorage(bytes32 _position) private pure returns (AllocationStrategyStorage storage $) {
        assembly {
            $.slot := _position
        }
    }
}
