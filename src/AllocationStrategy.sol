// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {WeightsLib, ValueCountHelper, ValueCount} from "./lib/WeightsLib.sol";
import {PackedBytes32, PackedBytes32x16} from "./lib/PackedLib.sol";

type ParamValue is uint16;

type ParamType is uint8; // max 16 types, store 16 uint16 in one bytes32
type ParamStrategy is uint8;

// type EntityParams is bytes32;

// should not be changed, rather add new values
enum ParamTypes_Module {
    DepositTargetShare,
    WithdrawalProtectShare
}

// should not be changed, used in storage
enum ParamTypes_Operator {
    Bond,
    Fee,
    Performance
}

// should not be changed, used in storage
enum ParamStrategies {
    Deposit,
    Withdrawal,
    Reward,
}


// fee = ValueCount.unpack(ParamRefs.feeIdx)

struct Entity {
    uint256 id;
    bool disabled;
    string name;
}

struct ParamTypeData {
    bool disabled;
    uint16 defValue; // default absolute values of params for entities, i.e. [bondIdx, feeIdx, perfIdx], according to `ParamTypes` enum
    string description; // e.g. "default", "high fee", "low performance"
}

// struct ParamData {
//     bool enabled;
//     string description; // e.g. "default", "high fee", "low performance"
//     ValueCount[] valueCounts; // array of value statistics, i.e. value and count pairs
// }

library ParamValueIdxsHelper {
    using PackedBytes32x16 for PackedBytes32;

    function getParamValueIndex(PackedBytes32 _self, ParamType _paramType) internal pure returns (uint16 idx) {
        return _self.unpack(ParamType.unwrap(_paramType));
    }

    function setParamValueIndex(PackedBytes32 _self, ParamType _paramType, uint16 idx)
        internal
        pure
        returns (PackedBytes32)
    {
        return _self.pack(ParamType.unwrap(_paramType), idx);
    }
}

library EntitiesStateStorage {
    struct DataStorage {
        PackedBytes32[] _entityParamValueIdxs; // array of entity IDs
    }

    /// TODO array slice, get param type from all
    /// TODO add entity
    /// TODO del entity
    /// TODO add param value
    /// TODO change param value

    function getStorage(bytes32 _position) internal view returns (PackedBytes32[] storage) {
        return _getDataStorage(_position)._entityParamValueIdxs;
    }

    function _getDataStorage(bytes32 _position) private pure returns (DataStorage storage $) {
        assembly {
            $.slot := _position
        }
    }
}

struct StrategyState {
    // uint64 paramsNonce; // nonce of params, used to recalculate weights
    PackedBytes32 _paramTypeMask; // mapping of strategies to packed bytes32, each uint16 represents a param type, zero value means skip params type for this strategy

}
// struct EntityParamsStorage {
//     Entity[] entities; //general info about entities
//     ParamValue[] defaultParamValues; // default absolute values of params for entities, i.e. [bondIdx, feeIdx, perfIdx], according to `ParamTypes` enum
//     PackedBytes32[] _entityParamValueIdxs; // array of entity's ParamValue indexes, i.e. [bondIdx, feeIdx, perfIdx] for each entity
//     mapping(ParamType => ValueCount[]) _paramValues;
// }

library ParamsStorage {
    struct DataStorage {
        Entity[] entities; //general info about entities
        ParamValue[] defaultParamValues; // default absolute values of params for entities, i.e. [bondIdx, feeIdx, perfIdx], according to `ParamTypes` enum
        PackedBytes32[] _entityParamValueIdxs; // array of entity's ParamValue indexes, i.e. [bondIdx, feeIdx, perfIdx] for each entity
        mapping(ParamType => ValueCount[]) _paramValues;
        mapping(ParamStrategy => PackedBytes32) _paramStrategiesMask; // mapping of strategies to packed bytes32, each uint16 represents a param type, zero value means skip params type for this strategy
    }

    // function setConfig(Storage storage self, uint8 key, Config memory config) internal {
    //         self.configs[key] = config;
    //     }

    // function getParamsData(Storage storage self, uint8 key) internal view returns (Config memory) {
    //     return self.configs[key];
    // }

    // function hasConfig(Storage storage self, uint8 key) internal view returns (bool) {
    //     // Проверка существования конфига
    //     return self.configs[key].value != 0 || self.configs[key].enabled;
    // }

    /// todo add param type
    /// todo add param value
    /// todo del param type
    /// todo del param value
    /// todo change param value
    /// todo



    function getParamTypeValueByIdx(bytes32 _position, ParamType _paramType, uint16 _idx)
        internal
        view
        returns (ValueCount)
    {
        return getParamValuesStorage(_position, _paramType)[_idx];
    }

    function getParamValuesStorage(bytes32 _position, ParamType _paramType) internal view returns (ValueCount[] storage) {
        return _getDataStorage(_position)._paramValues[_paramType];
    }

    function _getDataStorage(bytes32 _position) private pure returns (DataStorage storage $) {
        assembly {
            $.slot := _position
        }
    }
}

contract AllocationStrategy {
    using WeightsLib for uint16[];
    using WeightsLib for ValueCount[];
    using ValueCountHelper for ValueCount;

    // ...
    // значения каждого параметра лежат в отдельном массиве, длина которого равна количеству сущностей
    // при изменении количества сущностей, нужно обновить все массивы (добавление сущности делается просто через push, удаление - через помещение последнего элемента в место удаляемого и уменьшение длины массива на 1)

    // значения каждого параметра лежат в одном массиве, храним только уникальные значения и их количество, т.е. сразу структуру WeightsLib.ValueCount[]
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

    // каждый набор параметров задан в виде структуры, в которой хранятся массив со значениями, признак enabled и описание, массив коэффициентов, есть глобальный признак paramsNonce
    // при каждом изменении набора любых значений должен происходить пересчет набора коэффициентов и обновляться признак paramsNonce
    // когда требуется для сущности получить итоговый коэффициент, paramsNonce сверяется с сохраненным в сущности и если он не совпадает, то вычитываются все параметры для сущности, высчитывается
    // итоговый коэфф и сохраняется в сущности, а также обновляется paramsNonce в сущности

    //
    struct Storage {
        Entity[] entities;
        ParamValue[] defaultParams; // default params for entities, i.e. [bondIdx, feeIdx, perfIdx]
    }

    function getAllocExpo(uint16[] memory values, uint256 amount, uint64 r1)
        public
        pure
        returns (uint16[] memory idxs, ValueCount[] memory stat, uint256[] memory shares)
    {
        // ValueCount[] memory pts = values._compress();
        // pts[0] = ExpoAlloc32.Pair({value: 0,  count: 5});
        // pts[1] = ExpoAlloc32.Pair({value: 4200, count: 2});
        // pts[2] = ExpoAlloc32.Pair({value: 10000, count: 1});

        // pick your flavour: A=2, k=1e-4  ⇒ r = 2^0.0001 ≈ 1.000069
        // uint64 r = 4294970000; // pre-computed 32.32
        uint64 r = uint64(uint256(r1) * WeightsLib.SCALE / 1000000); // pre-computed 32.32
        uint64[] memory weights;
        (idxs, stat, weights) = values.getValueWeightsExp(r);

        shares = _getAllocation(amount, weights);
        // coef[i] * pot / 2^32 gives payout per *person* with pts[i].value
        // return (stat, shares);
    }

    function getAllocLinear(uint16[] memory values, uint256 amount)
        public
        pure
        returns (uint16[] memory idxs, ValueCount[] memory stat, uint256[] memory shares)
    {
        uint64[] memory weights;
        (idxs, stat, weights) = values.getValueWeights();

        shares = _getAllocation(amount, weights);
        // return (stat, shares);
    }

    function _getAllocation(uint256 amount, uint64[] memory weights) internal pure returns (uint256[] memory shares) {
        uint256 n = weights.length;
        shares = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            shares[i] = amount * weights[i] / WeightsLib.SCALE;
        }
    }

    function getValueCounts(uint16[] memory values)
        public
        pure
        returns (uint16[] memory idxs, ValueCount[] memory valCounts)
    {
        return values._compress();
    }
}
