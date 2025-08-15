// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ASCommon} from "./helpers/ASCommon.sol";
import {ASCore} from "../src/lib/as/ASCore.sol";

import {console2} from "forge-std/console2.sol";

contract WeightsAllocTest is ASCommon {
    using ASCore for bytes32;

    struct TestData {
        address[] addrs;
        uint16[][] catVals;
    }

    struct InitData {
        uint8[] sIds;
        uint8[] cIds;
        uint256[] eIds;
    }

    bytes32 private immutable AS_STORAGE =
        keccak256(abi.encode(uint256(keccak256(abi.encodePacked("AS.storage"))) - 1)) & ~bytes32(uint256(0xff));

    function setUp() public virtual override {
        super.setUp();
    }

    function test_AddStrategy() public {
        uint8[] memory sIds = new uint8[](2);
        sIds[0] = 1;
        sIds[1] = 2;
        // add 1st strategy "deposit"
        AS_STORAGE.enableStrategy(sIds[0], "Deposit");

        uint8[] memory s = AS_STORAGE.getEnabledStrategies();
        assertEq(s.length, 1, "Strategy count mismatch");
        assertEq(s[0], sIds[0], "Strategy ID mismatch");

        // add 2nd strategy "withdrawal"
        AS_STORAGE.enableStrategy(sIds[1], "Withdrawal");

        s = AS_STORAGE.getEnabledStrategies();
        assertEq(s.length, 2, "Strategy count mismatch");
        assertEq(s[1], sIds[1], "Strategy ID mismatch");

        emit log_named_array("Strategies", convertArrUint8toUint256(AS_STORAGE.getEnabledStrategies()));
    }

    function test_AddEntities() public {
        InitData memory _d;
        mockInit(_d);
        emit log_named_array("Strategies", convertArrUint8toUint256(AS_STORAGE.getEnabledStrategies()));
        emit log_named_array("Metrics", convertArrUint8toUint256(AS_STORAGE.getEnabledMetrics()));

        _d.eIds = new uint256[](5);
        _d.eIds[0] = 11;
        _d.eIds[1] = 22;
        _d.eIds[2] = 33;
        _d.eIds[3] = 44;
        _d.eIds[4] = 55;

        uint16[] memory vals1 = new uint16[](_d.cIds.length);
        uint16[] memory vals2 = new uint16[](_d.cIds.length);
        uint16[] memory vals3 = new uint16[](_d.cIds.length);
        uint16[] memory vals4 = new uint16[](_d.cIds.length);
        uint16[] memory vals5 = new uint16[](_d.cIds.length);
        vals1[0] = 230; // fee
        vals1[1] = 150; // tech
        vals1[2] = 100; // performance

        vals2[0] = 150; // fee
        vals2[1] = 100; // tech
        vals2[2] = 100; // performance

        vals3[0] = 170; // fee
        vals3[1] = 150; // tech
        vals3[2] = 80; // performance

        vals4[0] = 50; // fee
        vals4[1] = 100; // tech
        vals4[2] = 80; // performance

        vals5[0] = 110; // fee
        vals5[1] = 100; // tech
        vals5[2] = 0; // performance

        uint16[][] memory newVals = new uint16[][](_d.eIds.length);
        newVals[0] = vals1;
        newVals[1] = vals2;
        newVals[2] = vals3;
        newVals[3] = vals4;
        newVals[4] = vals5;

        // AS_STORAGE.disableMetric(_d.cIds[1]);
        // AS_STORAGE.disableMetric(_d.cIds[2]);

        AS_STORAGE.addEntities(_d.eIds, _d.cIds, newVals);

        for (uint8 i = 0; i < _d.eIds.length; i++) {
            uint256 eId = _d.eIds[i];
            uint16[] memory vals = AS_STORAGE.getMetricValues(eId);
            emit log_named_array(
                string(abi.encodePacked("Metric values for entity ", vm.toString(eId))), convertArrUint16toUint256(vals)
            );
        }
        ASCore.Strategy memory s = AS_STORAGE._getStrategyRaw(_d.sIds[0]);
        emit log_named_array(string(abi.encodePacked("[debug] sumX for metrics ")), convertArrFixed16ToUint256(s.sumX));

        for (uint8 i = 0; i < _d.sIds.length; i++) {
            uint8 sId = _d.sIds[i];
            (uint16[] memory weights, uint256 sumWeights) = AS_STORAGE.getWeights(sId);
            emit log_named_array(
                string(abi.encodePacked("Weights for strategy ", vm.toString(sId))), convertArrUint16toUint256(weights)
            );
            console2.log("sumWeights: %d", sumWeights);
        }
        for (uint8 i = 0; i < _d.eIds.length; i++) {
            uint256 eId = _d.eIds[i];

            uint256 share = Math.mulShr(AS_STORAGE.shareOf(eId, _d.sIds[0]), 1e18, 32, Math.Rounding.Ceil);
            console2.log("final shares for entity %d: 0.%d", eId, share);
            // emit log_named_array(string(abi.encodePacked("shares for entity ", vm.toString(eId))), share);
        }

        // uint256[] memory shares = AS_STORAGE.sharesOf(_d.eIds, _d.sIds[0]);

        uint256 totalAmount = 555000;
        uint256[] memory eIdsTarget = new uint256[](3);
        eIdsTarget[0] = _d.eIds[0];
        eIdsTarget[1] = _d.eIds[2];
        eIdsTarget[2] = _d.eIds[3];
        uint256[] memory shares = AS_STORAGE.sharesOf(eIdsTarget, _d.sIds[0]);
        uint256[] memory targets = new uint256[](eIdsTarget.length);

        for (uint256 i; i < eIdsTarget.length; ++i) {
            targets[i] = Math.mulShr(shares[i], totalAmount, 32, Math.Rounding.Ceil);
        }

        console2.log("totalAmount: %d", totalAmount);
        emit log_named_array(string(abi.encodePacked("entities")), eIdsTarget);
        emit log_named_array(string(abi.encodePacked("shares for entities")), shares);
        emit log_named_array(string(abi.encodePacked("targets for entities")), targets);
    }

    function _generateTargets(uint256 size) internal view returns (uint256[] memory) {
        uint256[] memory targets = new uint256[](size);
        uint256 seed = block.timestamp;

        for (uint256 i = 0; i < size; i++) {
            // Generate pseudo-random values between 100 and 10000
            seed = uint256(keccak256(abi.encode(seed, i)));
            targets[i] = (seed % 9900) + 100;
        }

        return targets;
    }

    function mockInit(InitData memory _d) internal returns (InitData memory) {
        _d.sIds = new uint8[](2);
        _d.sIds[0] = 0;
        _d.sIds[1] = 1;
        // add 1st strategy "deposit"
        AS_STORAGE.enableStrategy(_d.sIds[0], "Deposit");

        // add 3 metrics
        _d.cIds = new uint8[](3);
        _d.cIds[0] = 0;
        _d.cIds[1] = 1;
        _d.cIds[2] = 2;

        uint16[] memory weights = new uint16[](3);
        weights[0] = 30000;
        weights[1] = 20000;
        weights[2] = 20000;
        //  (1 - DVT, 0 - other)
        AS_STORAGE.enableMetric(_d.cIds[0], weights[0], "Fee");
        AS_STORAGE.enableMetric(_d.cIds[1], weights[1], "Technology");
        AS_STORAGE.enableMetric(_d.cIds[2], weights[2], "Performance");

        // add 2nd strategy "withdrawal"
        AS_STORAGE.enableStrategy(_d.sIds[1], "Withdrawal");

        weights[0] = 5000;
        weights[1] = 45000;
        weights[2] = 55000;

        AS_STORAGE.setWeights(_d.sIds[1], _d.cIds, weights);

        return _d;
    }

    // function _checkCatValue(
    //     uint32 entityId,
    //     uint16[] memory catVals,
    //     ValueCountWeight[][] memory vcWeights,
    //     uint256[] memory catValTotals
    // ) internal view {
    //     uint16[] memory idxs = _as.getEntCatIdxs(entityId);
    //     assertEq(idxs.length, catVals.length, "idxs/catVals length mismatch");
    //     Fixed32x32 weightCalc;
    //     for (uint256 i = 0; i < idxs.length; i++) {
    //         (uint16 value,, Fixed32x32 weight) = vcWeights[i][idxs[i]].unpack();
    //         weightCalc = Fixed32x32.wrap(uint64(catVals[i])).div(catValTotals[i]);

    //         assertEq(
    //             value,
    //             catVals[i],
    //             string(
    //                 abi.encodePacked(
    //                     "entity: ",
    //                     vm.toString(entityId),
    //                     " cat: ",
    //                     vm.toString(i),
    //                     " idx: ",
    //                     vm.toString(idxs[i]),
    //                     " value mismatch"
    //                 )
    //             )
    //         );
    //         assertEq(
    //             weight.unwrap(),
    //             weightCalc.unwrap(),
    //             string(
    //                 abi.encodePacked(
    //                     "entity: ",
    //                     vm.toString(entityId),
    //                     " cat: ",
    //                     vm.toString(i),
    //                     " idx: ",
    //                     vm.toString(idxs[i]),
    //                     " weight mismatch"
    //                 )
    //             )
    //         );
    //     }
    // }

    // function _arrUint256(uint16[] memory arr) internal pure returns (uint256[] memory) {
    //     uint256[] memory result = new uint256[](arr.length);
    //     for (uint256 i = 0; i < arr.length; i++) {
    //         result[i] = uint256(arr[i]);
    //     }
    //     return result;
    // }

    // function _arrVCWeights(ValueCountWeight[] memory arr) internal pure returns (uint256[] memory) {
    //     uint256[] memory result = new uint256[](arr.length);
    //     for (uint256 i = 0; i < arr.length; i++) {
    //         (uint16 value,,) = arr[i].unpack();
    //         result[i] = uint256(value);
    //     }
    //     return result;
    // }

    // function test_CatValuesWeights() public {
    //     (uint32 entityId0,, uint16[] memory catVals0) = _addEntity(0);
    //     (uint32 entityId1,, uint16[] memory catVals1) = _addEntity(1);
    //     (uint32 entityId2,, uint16[] memory catVals2) = _addEntity(2);

    //     (ValueCountWeight[] memory vcWeights1,) = _as.getCatValues(ModuleMetrics.DepositTargetShare);
    //     (ValueCountWeight[] memory vcWeights2,) = _as.getCatValues(ModuleMetrics.WithdrawalProtectShare);
    //     assertEq(vcWeights1.length, 3, "vcWeights1/entity count length mismatch");
    //     assertEq(vcWeights2.length, 3, "vcWeights2/entity count length mismatch");

    //     // for (uint256 i = 0; i < vcWeights1.length; i++) {
    //     //     (uint16 value, uint16 count, Fixed32x32 weight) = vcWeights1[i].unpack();
    //     //     console.log("vcWeights1[%d]", i);
    //     //     console.log("value=%d, count=%d, weight=%d", value, count, weight.unwrap());
    //     // }
    //     // for (uint256 i = 0; i < vcWeights2.length; i++) {
    //     //     (uint16 value, uint16 count, Fixed32x32 weight) = vcWeights2[i].unpack();
    //     //     console.log("vcWeights2[%d]", i);
    //     //     console.log("value=%d, count=%d, weight=%d", value, count, weight.unwrap());
    //     //     // console.log("value=%d, count=%d, weight=%d", value, count, weight.mul(10000));
    //     // }

    //     // emit log_array(_arrUint256(catVals0));
    //     // emit log_array(_arrUint256(catVals1));
    //     // emit log_array(_arrUint256(catVals2));

    //     ValueCountWeight[][] memory vcWeightsAll = new ValueCountWeight[][](CATS_COUNT);
    //     uint256[] memory catValTotals = new uint256[](CATS_COUNT);
    //     vcWeightsAll[0] = vcWeights1;
    //     vcWeightsAll[1] = vcWeights2;
    //     catValTotals[0] = catVals0[0] + catVals1[0] + catVals2[0];
    //     catValTotals[1] = catVals0[1] + catVals1[1] + catVals2[1];
    //     _checkCatValue(entityId0, catVals0, vcWeightsAll, catValTotals);
    //     _checkCatValue(entityId1, catVals1, vcWeightsAll, catValTotals);
    //     _checkCatValue(entityId2, catVals2, vcWeightsAll, catValTotals);

    //     // assertEq(vcWeights.length, 3, "vcWeights length mismatch");

    //     // assertEq(addedEntity.name, entity.name, "Entity name mismatch");
    //     // assertEq(addedEntity.disabled, entity.disabled, "Entity disabled state mismatch");
    //     // // Verify metric values were added
    //     // assertEq(addedCatVals.length, catVals.length, "Metric values length mismatch");
    //     // for (uint8 i = 0; i < catVals.length; i++) {
    //     //     // console.log("addedCatVals[%d]=", i, addedCatVals[i]);
    //     //     assertEq(addedCatVals[i], catVals[i], "Metric value mismatch");
    //     // }
    // }

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
    // uint8 constant CATS_COUNT = uint8(uint256(type(ModuleMetrics).max) + 1);

    // function _getMockData(uint256 _idx) internal pure returns (Entity memory entities, uint16[] memory catVals) {
    //     return (__getEntity(_idx), __getCatVals(_idx));
    // }

    // function __getEntity(uint256 _idx) internal pure returns (Entity memory) {
    //     Entity[] memory ents = new Entity[](MAX_ENTITIES);
    //     ents[0] = Entity({disabled: false, name: "Entity1"});
    //     ents[1] = Entity({disabled: false, name: "Entity2"});
    //     ents[2] = Entity({disabled: true, name: "Entity3"});
    //     ents[3] = Entity({disabled: false, name: "Entity4"});
    //     ents[4] = Entity({disabled: true, name: "Entity5"});
    //     return ents[_idx];
    // }

    // function __getCatVals(uint256 _idx) internal pure returns (uint16[] memory) {
    //     uint16[][] memory catVals = new uint16[][](MAX_ENTITIES);
    //     for (uint8 i = 0; i < MAX_ENTITIES; i++) {
    //         catVals[i] = new uint16[](CATS_COUNT);
    //     }
    //     // Entity 1
    //     catVals[0][uint8(ModuleMetrics.DepositTargetShare)] = 200; // 2%
    //     catVals[0][uint8(ModuleMetrics.WithdrawalProtectShare)] = 220;
    //     // Entity 2
    //     catVals[1][uint8(ModuleMetrics.DepositTargetShare)] = 300; // 3%
    //     catVals[1][uint8(ModuleMetrics.WithdrawalProtectShare)] = 350;
    //     // Entity 3
    //     catVals[2][uint8(ModuleMetrics.DepositTargetShare)] = 400; // 4%
    //     catVals[2][uint8(ModuleMetrics.WithdrawalProtectShare)] = 400;

    //     // Entity 4
    //     catVals[3][uint8(ModuleMetrics.DepositTargetShare)] = 500; // 5%
    //     catVals[3][uint8(ModuleMetrics.WithdrawalProtectShare)] = 500;
    //     // Entity 5
    //     catVals[4][uint8(ModuleMetrics.DepositTargetShare)] = 100; // 1%
    //     catVals[4][uint8(ModuleMetrics.WithdrawalProtectShare)] = 200; // 2%

    //     return catVals[_idx];
    // }

    // function _getAllocVals(ValueCountWeightStruct[] memory vcw) internal pure returns (uint16[] memory) {
    //     uint16 len;
    //     for (uint256 i = 0; i < vcw.length; i++) {
    //         len += vcw[i].count;
    //     }

    //     uint16[] memory allocVals = new uint16[](len);
    //     uint16 k;
    //     for (uint16 i = 0; i < vcw.length; i++) {
    //         for (uint16 j = 0; j < vcw[i].count; j++) {
    //             allocVals[k++] = vcw[i].value;
    //         }
    //     }
    //     return allocVals;
    // }

    // function _contains(uint256[] memory arr, uint256 x) internal pure returns (bool) {
    //     for (uint256 i = 0; i < arr.length; i++) {
    //         if (arr[i] == x) return true;
    //     }
    //     return false;
    // }
}
