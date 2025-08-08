// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

// import {console} from "forge-std/console.sol";
import {WeightsAlloc} from "./lib/WeightsAlloc.sol";
import {FixedBase} from "./lib/utils/FixedBase.sol";

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
    // using WeightsCalc for uint16[];
    // using WeightsCalc for ValueCountWeight[];
    using WeightsAlloc for bytes32;
    using FixedBase for uint256;

    bytes32 private immutable MODULE_AS_STORAGE =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("AS.storage"))) - 1)) & ~bytes32(uint256(0xff));

    constructor() {
        // uint16[] memory defaultValues = new uint16[](2);
        // defaultValues[uint8(ParamTypes_Module.DepositTargetShare)] = 2_00; // 2%%
        // defaultValues[uint8(ParamTypes_Module.WithdrawalProtectShare)] = 2_50; // 2.5%
    }

    function mockData() public {
        uint8[] memory sIds = new uint8[](2);
        sIds[0] = 1;
        sIds[1] = 2;
        // add 1st strategy "deposit"
        MODULE_AS_STORAGE.enableStrategy(
            sIds[0], WeightsAlloc.StrategyMetadata({id: sIds[0], owner: address(0), description: "Deposit"})
        );

        // console.log(); _named_array("Strategies", conversion(MODULE_AS_STORAGE.getEnabledStrategies()));
        // add 3 categories
        uint8[] memory cIds = new uint8[](3);
        cIds[0] = 1;
        cIds[1] = 2;
        cIds[2] = 3;

        uint16[] memory weights = new uint16[](3);
        weights[0] = uint16(FixedBase.fromUint(50, 16)); // 50 in Q16.16
        weights[1] = uint16(FixedBase.fromUint(20, 16)); // 20 in Q16.16
        weights[2] = uint16(FixedBase.fromUint(30, 16)); // 30 in Q16.16
        //  (1 - DVT, 0 - other)
        MODULE_AS_STORAGE.enableCategory(
            cIds[0], weights[0], WeightsAlloc.CategoryMetadata({id: cIds[0], owner: address(0), description: "Fee"})
        );
        MODULE_AS_STORAGE.enableCategory(
            cIds[1], weights[1], WeightsAlloc.CategoryMetadata({id: cIds[1], owner: address(0), description: "Technology"})
        );
        MODULE_AS_STORAGE.enableCategory(
            cIds[2], weights[2], WeightsAlloc.CategoryMetadata({id: cIds[2], owner: address(0), description: "Performance"})
        );

        // return MODULE_AS_STORAGE.getEnabledCategories();

        // add 2nd strategy "withdrawal"
        MODULE_AS_STORAGE.enableStrategy(
            sIds[1], WeightsAlloc.StrategyMetadata({id: sIds[1], owner: address(0), description: "Withdrawal"})
        );

        weights[0] = uint16(FixedBase.fromUint(40, 16)); // 2 in Q16.16
        weights[1] = uint16(FixedBase.fromUint(20, 16)); // 4 in Q16.16
        weights[2] = uint16(FixedBase.fromUint(40, 16)); // 6 in Q16.16

        MODULE_AS_STORAGE.setWeights(sIds[1], cIds, weights);

        // return MODULE_AS_STORAGE.getEnabledStrategies();
    }

    // function addEntity(Entity memory _ent, uint16[] memory _catVals) public returns (uint32 _idx) {
    //     return MODULE_AS_STORAGE.addEntity(_ent, _catVals);
    // }

    // function getEntity(uint32 _idx) public view returns (Entity memory, uint16[] memory) {
    //     return MODULE_AS_STORAGE.getEntity(_idx);
    // }

    // function getCatValues(ModuleCategories _cat)
    //     public
    //     view
    //     returns (ValueCountWeight[] memory vcWeights, bool isDirty)
    // {
    //     ValueCountWeight[] memory _vcWeights;
    //     (_vcWeights, isDirty) = MODULE_AS_STORAGE.getCategoryAllValueValueCountsWeights(Category.wrap(uint8(_cat)));
    //     return (_vcWeights, isDirty);
    // }

    // function getEntCatIdxs(uint32 _entityId) public view returns (uint16[] memory idxs) {
    //     return MODULE_AS_STORAGE.getEntityCategoryIdxs(_entityId);
    // }

    // function calcVC(uint16[] calldata values)
    //     public
    //     pure
    //     returns (uint16[] memory ecIdxs, ValueCountWeight[] memory vcWeights)
    // {
    //     return WeightsCalc.compressValues(values);
    // }

    // function calcAllocExpo(uint16[] calldata values, uint256 amount)
    //     public
    //     pure
    //     returns (uint16[] memory ecIdxs, ValueCountWeight[] memory vcWeights, uint256[] memory allocation)
    // {
    //     // w(v)=r^v, where `r=A^k`
    //     // e.g.: A=2, k=1e-4 => r = 2^0.0001 ≈ 1.000069 or pre-computed 32.32:uint64 r = 4294970000;
    //     // r = 1.1, 32.32:uint64 r = 4724464025
    //     Fixed32x32 r = Fixed32x32.wrap(4724464025); // pre-computed 32.32
    //     (ecIdxs, vcWeights) = values.getValueWeightsExp(r);
    //     allocation = calcAllocation(amount, vcWeights);
    // }

    // function calcAllocLinear(uint16[] calldata values, uint256 amount)
    //     public
    //     pure
    //     returns (uint16[] memory ecIdxs, ValueCountWeight[] memory vcWeights, uint256[] memory allocation)
    // {
    //     (ecIdxs, vcWeights) = values.getValueWeights();
    //     allocation = calcAllocation(amount, vcWeights);
    // }

    // function calcAllocation(uint256 amount, ValueCountWeight[] memory vcWeights)
    //     public
    //     pure
    //     returns (uint256[] memory allocation)
    // {
    //     uint256 n = vcWeights.length;
    //     allocation = new uint256[](n);
    //     //
    //     for (uint256 i; i < n; ++i) {
    //         allocation[i] = vcWeights[i].getW().mul(amount);
    //     }
    // }

    // function getConfig() public view returns (Config memory) {
    //     return MODULE_AS_STORAGE.getConfig();
    // }


}
