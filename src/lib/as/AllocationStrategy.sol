// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {PackedBytes32, PackedBytes32Helper} from "../utils/PackedBytes32.sol";
import {AllocationStrategyStorage, AllocationStrategyStorageHelper} from "./Storage.sol";
import {ValueCountWeight, ValueCountWeightHelper} from "./ValueCounterWeight.sol";
import {CategoryValuesState, CategoryValuesStateHelper} from "./CategoryValuesState.sol";
import {Category, CategoryValueIndexesHelper} from "./CategoryValueIndexes.sol";
import {WeightsCalc} from "./WeightsCalc.sol";
import {Config, Entity} from "./Types.sol";

library EntityCategoryValuesStorage {
    struct DataStorage {
        PackedBytes32[] _entityCategoryValueIndexes; // array of entity IDs
    }

    /// TODO array slice, get param type from all
    /// TODO add entity
    /// TODO del entity
    /// TODO add param value
    /// TODO change param value

    function getStorage(bytes32 _position) internal view returns (PackedBytes32[] storage) {
        return _getStorage(_position)._entityCategoryValueIndexes;
    }

    function _getStorage(bytes32 _position) private pure returns (DataStorage storage $) {
        assembly {
            $.slot := _position
        }
    }
}

library AllocationStrategyHelper {
    using CategoryValueIndexesHelper for PackedBytes32;
    using PackedBytes32Helper for PackedBytes32;

    using WeightsCalc for *;
    // using WeightsCalc for ValueCountWeight[];
    using ValueCountWeightHelper for ValueCountWeight;
    using CategoryValuesStateHelper for CategoryValuesState;
    using AllocationStrategyStorageHelper for *;

    error LengthMismatch();
    error OutOfBounds();

    function init(bytes32 _position, uint8 _categoriesCount) internal {
        assert(_categoriesCount <= PackedBytes32Helper.ELEMENT_COUNT); // max 16 types, store 16 uint16 in one bytes32
        Config storage cfg = _position.getAllocationStrategyStorage().getConfigStorage();

        cfg.categoriesCount = _categoriesCount;
        cfg.initialized = true; // mark config as initialized
        /// todo check if configured
    }

    function getEntity(bytes32 _position, uint32 entityId)
        internal
        view
        returns (Entity memory entity, uint16[] memory values)
    {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();

        Entity[] storage entities = $.getEntitiesStorage();
        if (entityId >= entities.length) {
            revert OutOfBounds();
        }
        entity = entities[entityId];
        values = _getEntityCategoryValues($, entityId);
    }

    function addEntity(bytes32 _position, Entity memory _entity, uint16[] memory newValues)
        internal
        returns (uint32 entityId)
    {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        Config storage cfg = $.getConfigStorage();
        Entity[] storage es = $.getEntitiesStorage();

        if (newValues.length != cfg.categoriesCount) {
            revert LengthMismatch();
        }
        // Add entity
        entityId = uint32(es.length);
        WeightsCalc.checkMaxCount(entityId + 1); // ensure we do not exceed max count of entities
        es.push(_entity);
        $.getEntityCategoryValueIndexesStorage().push(PackedBytes32.wrap(0)); // add new entity's category value indexes with zero values
        _updateEntityAllCategoryValues($, entityId, newValues, true); // update entity's category values
    }

    function getEntityCategoryIdxs(bytes32 _position, uint32 entityId) internal view returns (uint16[] memory idxs) {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        return _getEntityCategoryIdxs($, entityId);
    }

    function _getEntityCategoryIdxs(AllocationStrategyStorage storage $, uint32 entityId)
        internal
        view
        returns (uint16[] memory idxs)
    {
        Config storage cfg = $.getConfigStorage();
        return $.getEntityCategoryIdxs(entityId).unpack(cfg.categoriesCount);
    }

    function getEntityCategoryValues(bytes32 _position, uint32 entityId)
        internal
        view
        returns (uint16[] memory values)
    {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        return _getEntityCategoryValues($, entityId);
    }

    function _getEntityCategoryValues(AllocationStrategyStorage storage $, uint32 entityId)
        internal
        view
        returns (uint16[] memory values)
    {
        // temporary fill with indexes
        values = _getEntityCategoryIdxs($, entityId);
        CategoryValuesState storage cvs;
        // values = new uint16[](cnt);
        for (uint8 i = 0; i < values.length; ++i) {
            cvs = $.getCategoryValuesState(Category.wrap(i));
            uint16 idx = values[i];
            // replace index with value
            if (idx < cvs.vcWeights.length) {
                (values[i],) = cvs.vcWeights[idx].unpackVC();
            } else {
                values[i] = 0; // default value if index is out of bounds
            }
        }
        return values;
    }

    /// @notice Set parameter value for an entity
    /// @param _position Storage position
    /// @param entityId Entity ID
    /// @param category Parameter type
    /// @param newValue New parameter value
    function setEntityCategoryValue(bytes32 _position, uint32 entityId, Category category, uint16 newValue) internal {
        _updateEntityCategoryValue(_position.getAllocationStrategyStorage(), entityId, category, newValue, false);
    }

    function setEntityAllCategoryValues(bytes32 _position, uint32 entityId, uint16[] memory newValues) internal {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        _updateEntityAllCategoryValues($, entityId, newValues, false);
    }

    function _updateEntityCategoryValue(
        AllocationStrategyStorage storage $,
        uint32 entityId,
        Category category,
        uint16 newValue,
        bool isNew
    ) internal {
        PackedBytes32 cIdxs = $.getEntityCategoryIdxs(entityId);
        cIdxs = __updateEntityCategoryValueAndWeights($, category, newValue, cIdxs, isNew);
        // update entity's category indexes
        $.setEntityCategoryIdxs(entityId, cIdxs);
    }

    function _updateEntityAllCategoryValues(
        AllocationStrategyStorage storage $,
        uint32 entityId,
        uint16[] memory newValues,
        bool isNew
    ) internal {
        PackedBytes32 cIdxs = $.getEntityCategoryIdxs(entityId);
        // console.log("entityId=%d, before cIdxs:", entityId);
        // console.logBytes32(PackedBytes32.unwrap(cIdxs));

        for (uint8 i = 0; i < newValues.length; ++i) {
            cIdxs = __updateEntityCategoryValueAndWeights($, Category.wrap(i), newValues[i], cIdxs, isNew);
            // console.logBytes32(PackedBytes32.unwrap(cIdxs));
        }
        // update entity's category indexes
        $.setEntityCategoryIdxs(entityId, cIdxs);
    }

    function __updateEntityCategoryValueAndWeights(
        AllocationStrategyStorage storage $,
        Category category,
        uint16 newValue,
        PackedBytes32 cIdxs,
        bool isNew
    ) internal returns (PackedBytes32) {
        CategoryValuesState storage cvs = $.getCategoryValuesState(category);
        cIdxs = cvs._updateCategoryValueAndSetIndex(category, newValue, cIdxs, isNew);
        cvs._recalculateValueCountsWeights();
        return cIdxs;
    }

    function getCategoryAllValueValueCountsWeights(bytes32 _position, Category category)
        internal
        view
        returns (ValueCountWeight[] memory vcWeights, bool isDirty)
    {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        return _getCategoryAllValueCountsWeights($, category);
    }

    /// @notice Update parameter values for all entities of a specific parameter type
    /// @param _position Storage position
    /// @param category Parameter type to update
    /// @param newValues New values for all entities (array length must match entities count)
    function setCategoryAllValues(bytes32 _position, Category category, uint16[] memory newValues) internal {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        _setCategoryAllValues($, category, newValues);
    }

    function _getCategoryAllValueCountsWeights(AllocationStrategyStorage storage $, Category category)
        internal
        view
        returns (ValueCountWeight[] memory vcWeights, bool isDirty)
    {
        CategoryValuesState storage cvs = $.getCategoryValuesState(category);
        return cvs._getValueCountsWeights();
    }

    function _setCategoryAllValues(AllocationStrategyStorage storage $, Category category, uint16[] memory newValues)
        internal
    {
        CategoryValuesState storage cvs = $.getCategoryValuesState(category);
        PackedBytes32[] storage ecIdxs = $.getEntityCategoryValueIndexesStorage();

        uint256 length = ecIdxs.length;
        if (newValues.length != length) {
            revert LengthMismatch();
        }

        uint16[] memory idxs = cvs._setValueCountsWeights(newValues); // update value counts and weights

        // Update all entity param value indexes to use new indexes
        PackedBytes32[] memory newEcIdxs = new PackedBytes32[](length);
        for (uint16 i = 0; i < length; ++i) {
            // read old indexes and set new index for the category
            newEcIdxs[i] = ecIdxs[i].setIdx(category, idxs[i]);
        }
        // update entire entity category value indexes array at once
        $.setEntityCategoryValueIndexesStorage(newEcIdxs);
    }

    /// @notice Add a new parameter type with default value
    /// @param _position Storage position
    /// @return category The new parameter type ID
    function pushCategory(bytes32 _position) internal returns (Category category) {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        Config storage cfg = $.getConfigStorage();

        uint8 categoriesCount = cfg.categoriesCount;
        if (categoriesCount >= PackedBytes32Helper.ELEMENT_COUNT) {
            revert OutOfBounds();
        }
        category = Category.wrap(categoriesCount);
        unchecked {
            ++categoriesCount;
        }
        cfg.categoriesCount = categoriesCount;

        // Initialize param type vcWeightse with default value for all existing entities
        CategoryValuesState storage cvs = $.getCategoryValuesState(category);

        assert(cvs.vcWeights.length == 0); // should be empty before initialization
        Entity[] storage es = $.getEntitiesStorage();
        uint32 entityCnt = uint32(es.length);
        // Add zero value to index 0 with count equal to number of entities
        cvs.vcWeights.push(ValueCountWeightHelper.packVC(0, uint16(entityCnt)));
        cvs.isDirty = false; // reset dirty flag after update

        // TODO should be cleared on category removal? or here?
        if (entityCnt > 0) {
            PackedBytes32 cIdxs;
            // Update all entity param value indexes to reference index 0 for new param type
            for (uint32 i = 0; i < entityCnt; i++) {
                cIdxs = $.getEntityCategoryIdxs(i);
                if (cIdxs.getIdx(category) != 0) {
                    // update entity's category indexes
                    $.setEntityCategoryIdxs(i, cIdxs.setIdx(category, 0));
                }
            }
        }
    }

    /// @notice Remove a parameter type (can only remove the last one to avoid index shifting)
    /// @param _position Storage position
    function popCategory(bytes32 _position) internal {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        Config storage cfg = $.getConfigStorage();

        uint8 categoriesCount = cfg.categoriesCount;
        if (categoriesCount == 0) {
            revert OutOfBounds();
        }
        unchecked {
            --categoriesCount;
        }
        cfg.categoriesCount = categoriesCount;
        Category category = Category.wrap(categoriesCount);

        // Clear param type vcWeightse
        CategoryValuesState storage cvs = $.getCategoryValuesState(category);
        delete cvs.vcWeights; // Clear the array

        // Note: We don't clear entity param value indexes for gas efficiency
        // The removed param type indexes will simply be ignored when accessing
        // param values since categoriesCount is reduced
    }

    /// @notice Get current number of parameter types
    /// @param _position Storage position
    /// @return Number of parameter types
    function getConfig(bytes32 _position) internal view returns (Config memory) {
        AllocationStrategyStorage storage $ = _position.getAllocationStrategyStorage();
        return $.getConfigStorage();
    }

    function _getEntityCategoryValue(AllocationStrategyStorage storage $, uint32 entityId, Category category)
        internal
        view
        returns (uint16)
    {
        PackedBytes32 cIdxs = $.getEntityCategoryIdxs(entityId);
        uint16 valueIdx = cIdxs.getIdx(category);
        CategoryValuesState storage cvs = $.getCategoryValuesState(category);
        (uint16 value,) = cvs.vcWeights[valueIdx].unpackVC();
        return value;
    }

    // function _findNewIdxParamValue(ValueCountWeight[] storage vcWeights, uint16 idx, uint16 value)
    //     private
    //     returns (ValueCountWeight[] memory vcWeights, uint16)
    // {
    //     uint256 length = vcWeights.length;
    //     uint16 v;
    //     uint16 c;

    //     // reserve space for one more value
    //     vcWeights = new ValueCountWeight[](length + 1);
    //     // load current vcWeights
    //     uint256 i;
    //     for (i = 0; i < length; ++i) {
    //         vcWeights[i] = vcWeights[i];
    //     }

    //     // if (idx > 0) {
    //     //     unchecked {
    //     //         --idx;
    //     //     }
    //     if (idx < length) {
    //         (v, c) = vcWeights[idx].unpackVC();
    //         assert(value != v); // new value must be different from old value
    //         assert(c > 0); // check consistency
    //         unchecked {
    //             --c; // decrease count for old value
    //         }

    //         vcWeights[idx] = ValueCountWeightHelper.packVC(v, c);
    //         // save to storage
    //         vcWeights[idx] = vcWeights[idx];
    //     }
    //     // }

    //     idx = 0; // reset old index to 0, using it as a index of first element with zero count
    //     // First, try to find existing value

    //     for (i = 0; i < length; ++i) {
    //         (v, c) = vcWeights[i].unpackVC();
    //         if (v == value) {
    //             // Found existing value, increment count

    //             vcWeights[i] = ValueCountWeightHelper.packVC(value, c + 1);
    //             // save to storage
    //             vcWeights[i] = vcWeights[i];
    //             // return uint16(i);
    //             break;
    //         } else if (c == 0 && idx == 0) {
    //             // Remember first zero count index
    //             idx = uint16(i + 1); // store as 1-based index
    //         }
    //     }

    //     if (i == length) {
    //         if (idx > 0) {
    //             unchecked {
    //                 --idx; // switch to 0-based index
    //             }
    //             // Found a slot with count = 0, reuse it
    //             vcWeights[idx] = ValueCountWeightHelper.packVC(value, c + 1);
    //             vcWeights[idx] = ValueCountWeightHelper.packVC(value, 1);
    //             return uint16(idx);
    //         } else {
    //             // No existing value and no empty slots, add new entry
    //             vcWeights.push(ValueCountWeightHelper.packVC(value, 1));
    //             return uint16(length);
    //         }
    //     } else {
    //         assembly {
    //             // в первом слове массива хранится length
    //             mstore(vcWeights, newLen)
    //         }
    //         // Found existing value, increment count
    //         // return uint16(i);
    //         return idx; // return the index of the found value
    //     }
    // }

    // function _saveVCW(
    //     ValueCountWeight[] memory vcWeights,
    //     ValueCountWeight[] storage vcWeights,
    //     uint16 idx,
    //     uint16 value,
    //     uint16 _c
    // ) internal {
    //     ValueCountWeight vcw = vcWeights[idx];
    //     // save to storage
    //     vcWeights[idx] = vcw;
    //     if (idx < vcWeights.length - 1) {
    //         vcWeights[idx] = vcw;
    //     } else {
    //         vcWeights.push(vcw);
    //     }
    // }
}

// ...
// значения каждого параметра лежат в отдельном массиве, длина которого равна количеству сущностей
// при изменении количества сущностей, нужно обновить все массивы (добавление сущности делается просто через push, удаление - через помещение последнего элемента в место удаляемого и уменьшение длины массива на 1)

// значения каждого параметра лежат в одном массиве, храним только уникальные значения и их количество, т.е. сразу структуру WeightsCalc.ValueCountWeight[]
// внутри каждой сущности хранится индекс в этом массиве, а не значение
// нужно иметь набор индексов на значения параметров, определяющих default набор

// при установке параметра для сущности, нужно найти это значение в имеющемся массиве, увеличить счетчик его использование и прописать его индекс в сущность, если значение не найдено -  добавить значение в массив,
// одновременно найти предыдущее значение параметра для этой сущности, уменьшить счетчик его использования, если счетчик стал 0 - удалить значение из массива.
// (при удалении, старое значение не надо искать поиском, тк оно уже есть в сущности, и мы просто уменьшаем счетчик использования)
// однако мы не можем просто удалить значение из массива, т.к. это нарушит индексы, которые уже прописаны в других сущностях
// можно оставить значение в массиве, но count = 0, однако со временем массив будет расти, и это неэффективно
// можно сделать так, что при добавлении нового значения, мы будем проверять, есть ли в массиве значение с count = 0, и если есть - заменим его на новое значение
// ИЛИ можно хранить маппинг некоторого порядкового номера к индексу в массиве значений, т.е. внутри сущности хранится не индекс элемента, а его номер, который ссылается на индекс.
// порядковый номер инкрементируется при добавлении значения в массив, и новый индекс добавляется в маппинг, а номер в сущность.
// при удалении значения в массиве (когда каунтер = 0), на место удаленного элемента встает последний, следовательно в маппинге номеров, надо найти номер ссылавшийся на последний элемент и в нем заменить индекс,
// номер просто удаляем и при добавлении нового значения, просто заменять значение по этому индексу

// значение в маппинге,

// количество разных значений формально ограничено 10000, хотя для хранения используется uint16, т.е. 65536 значений

// каждый набор параметров задан в виде структуры, в которой хранятся массив со значениями, признак enabled и описание, массив коэффициентов, есть глобальный признак nonce
// при каждом изменении набора любых значений должен происходить пересчет набора коэффициентов и обновляться признак nonce
// когда требуется для сущности получить итоговый коэффициент, nonce сверяется с сохраненным в сущности и если он не совпадает, то вычитываются все параметры для сущности, высчитывается
// итоговый коэфф и сохраняется в сущности, а также обновляется nonce в сущности
