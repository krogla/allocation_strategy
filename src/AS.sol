// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {Fixed32x32Helper, Fixed32x32} from "./lib/utils/Fixed32x32.sol";
import {WeightsCalc} from "./lib/as/WeightsCalc.sol";
import {Entity, Config, Category} from "./lib/as/Types.sol";
import {AllocationStrategyHelper} from "./lib/as/AllocationStrategy.sol";
import {ValueCountWeightHelper, ValueCountWeight, ValueCountWeightStruct} from "./lib/as/ValueCounterWeight.sol";
// import {AllocationStrategyStorage, AllocationStrategyStorageHelper} from "./lib/as/Storage.sol";

// should not be changed, rather add new values
enum ModuleCategories {
    DepositTargetShare,
    WithdrawalProtectShare
}

// should not be changed, used in storage
enum OperatorCategories {
    Bond,
    Fee,
    Performance
}

// should not be changed, used in storage
enum ModuleStrategies {
    Deposit,
    Withdrawal,
    Reward
}

contract AS {
    using WeightsCalc for uint16[];
    using WeightsCalc for ValueCountWeight[];
    using ValueCountWeightHelper for ValueCountWeight;
    using Fixed32x32Helper for Fixed32x32;
    using AllocationStrategyHelper for bytes32;

    bytes32 private immutable MODULE_AS_STORAGE =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("ModuleAS.storage"))) - 1)) & ~bytes32(uint256(0xff));

    constructor() {
        // uint16[] memory defaultValues = new uint16[](2);
        // defaultValues[uint8(ParamTypes_Module.DepositTargetShare)] = 2_00; // 2%%
        // defaultValues[uint8(ParamTypes_Module.WithdrawalProtectShare)] = 2_50; // 2.5%

        uint8 catCount = uint8(type(ModuleCategories).max) + 1;
        MODULE_AS_STORAGE.init(catCount); // max 16 categories
    }

    function addEntity(Entity memory _ent, uint16[] memory _catVals) public returns (uint32 _idx) {
        return MODULE_AS_STORAGE.addEntity(_ent, _catVals);
    }

    function getEntity(uint32 _idx) public view returns (Entity memory, uint16[] memory) {
        return MODULE_AS_STORAGE.getEntity(_idx);
    }

    function getCatValues(ModuleCategories _cat)
        public
        view
        returns (ValueCountWeight[] memory vcWeights, bool isDirty)
    {
        ValueCountWeight[] memory _vcWeights;
        (_vcWeights, isDirty) = MODULE_AS_STORAGE.getCategoryAllValueValueCountsWeights(Category.wrap(uint8(_cat)));
        return (_vcWeights, isDirty);
    }

    function getEntCatIdxs(uint32 _entityId) public view returns (uint16[] memory idxs) {
        return MODULE_AS_STORAGE.getEntityCategoryIdxs(_entityId);
    }

    function calcVC(uint16[] calldata values)
        public
        pure
        returns (uint16[] memory ecIdxs, ValueCountWeight[] memory vcWeights)
    {
        return WeightsCalc.compressValues(values);
    }

    function calcAllocExpo(uint16[] calldata values, uint256 amount)
        public
        pure
        returns (uint16[] memory ecIdxs, ValueCountWeight[] memory vcWeights, uint256[] memory allocation)
    {
        // w(v)=r^v, where `r=A^k`
        // e.g.: A=2, k=1e-4 => r = 2^0.0001 ≈ 1.000069 or pre-computed 32.32:uint64 r = 4294970000;
        // r = 1.1, 32.32:uint64 r = 4724464025
        Fixed32x32 r = Fixed32x32.wrap(4724464025); // pre-computed 32.32
        (ecIdxs, vcWeights) = values.getValueWeightsExp(r);
        allocation = calcAllocation(amount, vcWeights);
    }

    function calcAllocLinear(uint16[] calldata values, uint256 amount)
        public
        pure
        returns (uint16[] memory ecIdxs, ValueCountWeight[] memory vcWeights, uint256[] memory allocation)
    {
        (ecIdxs, vcWeights) = values.getValueWeights();
        allocation = calcAllocation(amount, vcWeights);
    }

    function calcAllocation(uint256 amount, ValueCountWeight[] memory vcWeights)
        public
        pure
        returns (uint256[] memory allocation)
    {
        uint256 n = vcWeights.length;
        allocation = new uint256[](n);
        //
        for (uint256 i; i < n; ++i) {
            allocation[i] = vcWeights[i].getW().mul(amount);
        }
    }

    function getConfig() public view returns (Config memory) {
        return MODULE_AS_STORAGE.getConfig();
    }
}
