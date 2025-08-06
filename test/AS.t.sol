// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/Test.sol";
import {ASCommon} from "./helpers/ASCommon.sol";
import {AS, ModuleCategories} from "../src/AS.sol";
import {Config, Entity} from "../src/lib/as/Types.sol";
import {Fixed32x32, Fixed32x32Helper} from "../src/lib/utils/Fixed32x32.sol";
// import {WeightsCalc} from "../src/lib/WeightsCalc.sol";
import {ValueCountWeightHelper, ValueCountWeight, ValueCountWeightStruct} from "../src/lib/as/ValueCounterWeight.sol";

contract ASTest is ASCommon {
    using stdJson for string;
    using ValueCountWeightHelper for ValueCountWeight;
    using Fixed32x32Helper for *;

    struct TestData {
        address[] addrs;
        uint16[][] catVals;
    }

    AS public _as;

    function setUp() public virtual override {
        super.setUp();
        _as = new AS();
    }

    function test_GetAllocation() public view {
        ValueCountWeightStruct[] memory vcw = new ValueCountWeightStruct[](3);
        vcw[0] = ValueCountWeightStruct(10, 1, Fixed32x32.wrap(214748364)); // 5% Fixed32x32 = 0.05 * 2**32
        vcw[1] = ValueCountWeightStruct(20, 2, Fixed32x32.wrap(429496729)); // 10% Fixed32x32 = 0.1 * 2**32
        vcw[2] = ValueCountWeightStruct(150, 1, Fixed32x32.wrap(3221225472)); // 75% Fixed32x32 = 0.75 * 2**32

        uint256 amount = 1000000;
        uint16[] memory allocVals = _getAllocVals(vcw);

        // for (uint256 i = 0; i < allocVals.length; i++) {
        //     console.log("vals[%d]=", i, allocVals[i]);
        // }

        (uint16[] memory ecIdxs, ValueCountWeight[] memory vcWeights, uint256[] memory allocation) =
            _as.calcAllocLinear(allocVals, amount);
        // for (uint256 i = 0; i < vcWeights.length; i++) {
        //     (uint16 value, uint16 count, Fixed32x32 weight) = vcWeights[i].unpack();
        //     console.log("vcw %d:", i);
        //     console.log("%d %d %d", value, count, weight.unwrap());
        // }

        assertEq(vcWeights.length, 3, "vcWeights length mismatch");
        for (uint256 i = 0; i < 3; i++) {
            (uint16 value, uint16 count, Fixed32x32 weight) = vcWeights[i].unpack();
            assertEq(value, vcw[i].value, "vcw value mismatch");
            assertEq(count, vcw[i].count, "vcw count mismatch");
            assertEq(weight.unwrap(), vcw[i].weight.unwrap(), "vcw weight mismatch");
        }

        assertEq(ecIdxs.length, 4, "ecIdxs<>vals length mismatch");
        for (uint256 i = 0; i < ecIdxs.length; i++) {
            (uint16 value,) = vcWeights[ecIdxs[i]].unpackVC();
            assertEq(value, allocVals[i], "ecIdxs mismatch");
        }
    }

    function test_GetConfig() public view {
        Config memory conf = _as.getConfig();
        assertEq(conf.initialized, true, "Config should be initialized");
        assertEq(conf.categoriesCount, uint8(type(ModuleCategories).max) + 1, "Module categories count mismatch");
    }

    function test_AddEntity() public {
        (uint32 entityId, Entity memory entity, uint16[] memory catVals) = _addEntity(0);
        // Verify entity was added
        (Entity memory addedEntity, uint16[] memory addedCatVals) = _as.getEntity(entityId);

        assertEq(addedEntity.name, entity.name, "Entity name mismatch");
        assertEq(addedEntity.disabled, entity.disabled, "Entity disabled state mismatch");
        // Verify category values were added
        assertEq(addedCatVals.length, catVals.length, "Category values length mismatch");
        for (uint8 i = 0; i < catVals.length; i++) {
            // console.log("addedCatVals[%d]=", i, addedCatVals[i]);
            assertEq(addedCatVals[i], catVals[i], "Category value mismatch");
        }

        (ValueCountWeight[] memory vcWeights, bool isDirty) = _as.getCatValues(ModuleCategories.DepositTargetShare);
        assertEq(isDirty, false, "isDirty should be false");
        assertEq(vcWeights.length, 1, "vcWeights/entity count length mismatch");
        (uint16 value, uint16 count, Fixed32x32 weight) = vcWeights[0].unpack();
        assertEq(value, catVals[0], "vcWeights value mismatch");
        assertEq(count, 1, "vcWeights count mismatch");
        assertEq(weight.unwrap(), Fixed32x32.wrap(2 ** 32).unwrap(), "vcWeights weight should be 1.0 (2^32)");
    }

    function _addEntity(uint256 idx)
        internal
        returns (uint32 entityId, Entity memory entity, uint16[] memory catVals)
    {
        (entity, catVals) = _getMockData(idx);
        entityId = _as.addEntity(entity, catVals);
    }

    function _checkCatValue(
        uint32 entityId,
        uint16[] memory catVals,
        ValueCountWeight[][] memory vcWeights,
        uint256[] memory catValTotals
    ) internal view {
        uint16[] memory idxs = _as.getEntCatIdxs(entityId);
        assertEq(idxs.length, catVals.length, "idxs/catVals length mismatch");
        Fixed32x32 weightCalc;
        for (uint256 i = 0; i < idxs.length; i++) {
            (uint16 value,, Fixed32x32 weight) = vcWeights[i][idxs[i]].unpack();
            weightCalc = Fixed32x32.wrap(uint64(catVals[i])).div(catValTotals[i]);

            assertEq(
                value,
                catVals[i],
                string(
                    abi.encodePacked(
                        "entity: ",
                        vm.toString(entityId),
                        " cat: ",
                        vm.toString(i),
                        " idx: ",
                        vm.toString(idxs[i]),
                        " value mismatch"
                    )
                )
            );
            assertEq(
                weight.unwrap(),
                weightCalc.unwrap(),
                string(
                    abi.encodePacked(
                        "entity: ",
                        vm.toString(entityId),
                        " cat: ",
                        vm.toString(i),
                        " idx: ",
                        vm.toString(idxs[i]),
                        " weight mismatch"
                    )
                )
            );
        }
    }

    function _arrUint256(uint16[] memory arr) internal pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            result[i] = uint256(arr[i]);
        }
        return result;
    }

    function _arrVCWeights(ValueCountWeight[] memory arr) internal pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            (uint16 value,,) = arr[i].unpack();
            result[i] = uint256(value);
        }
        return result;
    }

    function test_CatValuesWeights() public {
        (uint32 entityId0,, uint16[] memory catVals0) = _addEntity(0);
        (uint32 entityId1,, uint16[] memory catVals1) = _addEntity(1);
        (uint32 entityId2,, uint16[] memory catVals2) = _addEntity(2);

        (ValueCountWeight[] memory vcWeights1,) = _as.getCatValues(ModuleCategories.DepositTargetShare);
        (ValueCountWeight[] memory vcWeights2,) = _as.getCatValues(ModuleCategories.WithdrawalProtectShare);
        assertEq(vcWeights1.length, 3, "vcWeights1/entity count length mismatch");
        assertEq(vcWeights2.length, 3, "vcWeights2/entity count length mismatch");

        // for (uint256 i = 0; i < vcWeights1.length; i++) {
        //     (uint16 value, uint16 count, Fixed32x32 weight) = vcWeights1[i].unpack();
        //     console.log("vcWeights1[%d]", i);
        //     console.log("value=%d, count=%d, weight=%d", value, count, weight.unwrap());
        // }
        // for (uint256 i = 0; i < vcWeights2.length; i++) {
        //     (uint16 value, uint16 count, Fixed32x32 weight) = vcWeights2[i].unpack();
        //     console.log("vcWeights2[%d]", i);
        //     console.log("value=%d, count=%d, weight=%d", value, count, weight.unwrap());
        //     // console.log("value=%d, count=%d, weight=%d", value, count, weight.mul(10000));
        // }

        // emit log_array(_arrUint256(catVals0));
        // emit log_array(_arrUint256(catVals1));
        // emit log_array(_arrUint256(catVals2));

        ValueCountWeight[][] memory vcWeightsAll = new ValueCountWeight[][](CATS_COUNT);
        uint256[] memory catValTotals = new uint256[](CATS_COUNT);
        vcWeightsAll[0] = vcWeights1;
        vcWeightsAll[1] = vcWeights2;
        catValTotals[0] = catVals0[0] + catVals1[0] + catVals2[0];
        catValTotals[1] = catVals0[1] + catVals1[1] + catVals2[1];
        _checkCatValue(entityId0, catVals0, vcWeightsAll, catValTotals);
        _checkCatValue(entityId1, catVals1, vcWeightsAll, catValTotals);
        _checkCatValue(entityId2, catVals2, vcWeightsAll, catValTotals);

        // assertEq(vcWeights.length, 3, "vcWeights length mismatch");

        // assertEq(addedEntity.name, entity.name, "Entity name mismatch");
        // assertEq(addedEntity.disabled, entity.disabled, "Entity disabled state mismatch");
        // // Verify category values were added
        // assertEq(addedCatVals.length, catVals.length, "Category values length mismatch");
        // for (uint8 i = 0; i < catVals.length; i++) {
        //     // console.log("addedCatVals[%d]=", i, addedCatVals[i]);
        //     assertEq(addedCatVals[i], catVals[i], "Category value mismatch");
        // }
    }

    // function test_OptIn_RevertWhen_ZeroManagerAddress() public {
    //     vm.expectRevert(CCR.ZeroOperatorManagerAddress.selector);
    //     ccr.optIn({moduleId: csmId, operatorId: noCsm1Id, manager: address(0), indexStart: 2, indexEnd: 4, rpcURL: ""});
    // }

    // function test_OptIn_RevertWhen_WrongRewardAddress() public {
    //     vm.prank(stranger1);
    //     vm.expectRevert(CCR.RewardAddressMismatch.selector);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });
    // }

    // function test_OptIn_RevertWhen_WrongModuleId() public {
    //     vm.prank(noCsm1);
    //     vm.expectRevert(IStakingRouter.StakingModuleUnregistered.selector);
    //     ccr.optIn({moduleId: 999, operatorId: noCsm1Id, manager: noCsm1Manager, indexStart: 2, indexEnd: 4, rpcURL: ""});
    // }

    // function test_OptIn_RevertWhen_LidoOperatorNotActive() public {
    //     // set noCsm1 to inactive
    //     updateNoActive(csm, noCsm1Id, false);

    //     vm.prank(noCsm1);
    //     vm.expectRevert(CCR.OperatorNotActive.selector);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });
    // }

    // function test_OptIn_RevertWhen_OperatorAlreadyOptedIn() public {
    //     // optin
    //     vm.prank(noCsm1);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });

    //     // repeat optin
    //     vm.prank(noCsm1);
    //     vm.expectRevert(CCR.OperatorOptedIn.selector);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });
    // }

    // function test_OptIn_RevertWhen_OperatorForceOptedOut() public {
    //     // optin
    //     vm.prank(noCsm1);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });

    //     // force optout
    //     vm.roll(block.number + 100);
    //     vm.prank(committee);
    //     ccr.optOut({moduleId: csmId, operatorId: noCsm1Id});

    //     // repeat optin
    //     vm.roll(block.number + 100);
    //     vm.prank(noCsm1);
    //     vm.expectRevert(CCR.OperatorBlocked.selector);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });
    // }

    // function test_OptIn_RevertWhen_ManagerBelongsOtherOperator() public {
    //     // optin
    //     vm.prank(noCurated1);
    //     ccr.optIn({
    //         moduleId: norId,
    //         operatorId: noCurated1Id,
    //         manager: noCurated1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });

    //     // optin with same manager
    //     vm.prank(noCsm1);
    //     vm.expectRevert(ICCROperatorStatesStorage.ManagerBelongsToOtherOperator.selector);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCurated1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: ""
    //     });
    // }

    // function test_OptIn_RevertWhen_KeyIndexWrongOrder() public {
    //     // optin
    //     vm.prank(noCsm1);
    //     vm.expectRevert(CCR.KeyIndexMismatch.selector);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 4,
    //         indexEnd: 2,
    //         rpcURL: ""
    //     });
    // }

    // function test_OptIn_RevertWhen_KeyIndexOutOfRange() public {
    //     // optin
    //     vm.prank(noCsm1);
    //     vm.expectRevert(CCR.KeyIndexOutOfRange.selector);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 100,
    //         rpcURL: ""
    //     });
    // }

    // function test_getOperatorIsEnabledForPreconf() public {
    //     // wrong op id
    //     // assertFalse(ccr.getOperatorIsEnabledForPreconf(csmId, 999));

    //     // not yet opted in
    //     assertFalse(ccr.getOperatorIsEnabledForPreconf(csmId, noCsm1Id));
    //     // opt in on behalf of noCsm1
    //     vm.prank(noCsm1);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: rpcUrl1
    //     });
    //     // opted in
    //     assertTrue(ccr.getOperatorIsEnabledForPreconf(csmId, noCsm1Id));
    // }

    // function test_GetOperatorAllowedKeys() public {
    //     vm.prank(committee);
    //     ccr.setModuleConfig(csmId, true, 0, 0);
    //     // 0 for disabled module
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), 0);

    //     vm.prank(committee);
    //     ccr.setModuleConfig(csmId, false, 0, 0);

    //     // set noCsm1 to inactive
    //     updateNoActive(csm, noCsm1Id, false);
    //     // 0 for inactive operator
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), 0);
    //     updateNoActive(csm, noCsm1Id, true);

    //     /// operator NOT yet opted in
    //     ///
    //     vm.prank(committee);
    //     ccr.setConfig(0, 0, opKeysCount - 1, defaultBlockGasLimit);

    //     // operatorMaxKeys when operatorMaxKeys < operatorTotalAddedKeys
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), opKeysCount - 1);

    //     vm.prank(committee);
    //     ccr.setConfig(0, 99, defaultOperatorMaxKeys, defaultBlockGasLimit);

    //     // operatorTotalAddedKeys when operatorMaxKeys > operatorTotalAddedKeys
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), opKeysCount);

    //     // opt in on behalf of noCsm1 with 3 keys
    //     vm.prank(noCsm1);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 2,
    //         indexEnd: 4,
    //         rpcURL: rpcUrl1
    //     });

    //     // operatorMaxKeys > operatorTotalAddedKeys
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), opKeysCount - 3);

    //     // voluntary opt out
    //     vm.roll(block.number + 100);
    //     vm.prank(noCsm1Manager);
    //     ccr.optOut();

    //     vm.roll(block.number + 100);
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), opKeysCount);

    //     // opt in on behalf of noCsm1 with 9 keys
    //     vm.prank(noCsm1);
    //     ccr.optIn({
    //         moduleId: csmId,
    //         operatorId: noCsm1Id,
    //         manager: noCsm1Manager,
    //         indexStart: 0,
    //         indexEnd: 8,
    //         rpcURL: rpcUrl1
    //     });
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), opKeysCount - 9);

    //     // reduce max operator keys in module config to 5
    //     vm.prank(committee);
    //     ccr.setModuleConfig(csmId, false, 5, 0);
    //     // operator opted in totalKeys > operatorMaxKeys
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), 0);

    //     // force optout
    //     vm.roll(block.number + 100);
    //     vm.prank(committee);
    //     ccr.optOut({moduleId: csmId, operatorId: noCsm1Id});

    //     // optOut finished, but forced optout
    //     vm.roll(block.number + 100);
    //     assertEq(ccr.getOperatorAllowedKeys(csmId, noCsm1Id), 0);
    // }

    /// MOCK DATA HELPERS

    uint256 constant MAX_ENTITIES = 5;
    uint8 constant CATS_COUNT = uint8(uint256(type(ModuleCategories).max) + 1);

    function _getMockData(uint256 _idx) internal pure returns (Entity memory entities, uint16[] memory catVals) {
        return (__getEntity(_idx), __getCatVals(_idx));
    }

    function __getEntity(uint256 _idx) internal pure returns (Entity memory) {
        Entity[] memory ents = new Entity[](MAX_ENTITIES);
        ents[0] = Entity({disabled: false, name: "Entity1"});
        ents[1] = Entity({disabled: false, name: "Entity2"});
        ents[2] = Entity({disabled: true, name: "Entity3"});
        ents[3] = Entity({disabled: false, name: "Entity4"});
        ents[4] = Entity({disabled: true, name: "Entity5"});
        return ents[_idx];
    }

    function __getCatVals(uint256 _idx) internal pure returns (uint16[] memory) {
        uint16[][] memory catVals = new uint16[][](MAX_ENTITIES);
        for (uint8 i = 0; i < MAX_ENTITIES; i++) {
            catVals[i] = new uint16[](CATS_COUNT);
        }
        // Entity 1
        catVals[0][uint8(ModuleCategories.DepositTargetShare)] = 200; // 2%
        catVals[0][uint8(ModuleCategories.WithdrawalProtectShare)] = 220;
        // Entity 2
        catVals[1][uint8(ModuleCategories.DepositTargetShare)] = 300; // 3%
        catVals[1][uint8(ModuleCategories.WithdrawalProtectShare)] = 350;
        // Entity 3
        catVals[2][uint8(ModuleCategories.DepositTargetShare)] = 400; // 4%
        catVals[2][uint8(ModuleCategories.WithdrawalProtectShare)] = 400;

        // Entity 4
        catVals[3][uint8(ModuleCategories.DepositTargetShare)] = 500; // 5%
        catVals[3][uint8(ModuleCategories.WithdrawalProtectShare)] = 500;
        // Entity 5
        catVals[4][uint8(ModuleCategories.DepositTargetShare)] = 100; // 1%
        catVals[4][uint8(ModuleCategories.WithdrawalProtectShare)] = 200; // 2%

        return catVals[_idx];
    }

    function _getAllocVals(ValueCountWeightStruct[] memory vcw) internal pure returns (uint16[] memory) {
        uint16 len;
        for (uint256 i = 0; i < vcw.length; i++) {
            len += vcw[i].count;
        }

        uint16[] memory allocVals = new uint16[](len);
        uint16 k;
        for (uint16 i = 0; i < vcw.length; i++) {
            for (uint16 j = 0; j < vcw[i].count; j++) {
                allocVals[k++] = vcw[i].value;
            }
        }
        return allocVals;
    }

    function _contains(uint256[] memory arr, uint256 x) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == x) return true;
        }
        return false;
    }
}
