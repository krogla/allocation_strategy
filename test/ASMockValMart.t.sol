// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ASCommon} from "./helpers/ASCommon.sol";
import {ASCore} from "../src/lib/as/ASCore.sol";
import {ASConvertor} from "../src/lib/as/ASConvertor.sol";
import {ASMockValMart} from "../src/ASMockValMart.sol";

import {console2} from "forge-std/console2.sol";

contract ASTest is ASCommon {
    using ASCore for bytes32;

    ASMockValMart public _as;

    function setUp() public virtual override {
        super.setUp();
        _as = new ASMockValMart();
    }

    function test_AddMetricsAndStrategies() public {
        _as.mock_init();

        (, uint8[] memory cIds, uint8[] memory sIds) = _as.getIds();
        assertEq(sIds.length, 2, "Strategies (Operators) count mismatch");
        assertEq(cIds.length, 3, "Metrics (Operators) count mismatch");

        emit log_named_array("Strategies (Operators)", convertArrUint8toUint256(sIds));
        emit log_named_array("Metrics (Operators)", convertArrUint8toUint256(cIds));
    }

    function test_AddEntities() public {
        _as.mock_init();
        _as.mock_addEntities();

        (uint256[] memory eIds,, uint8[] memory sIds) = _as.getIds();

        assertEq(eIds.length, 5, "Entities (Operators) count mismatch");
        emit log_named_array("Entities (Operators)", eIds);

        uint256[] memory shares;
        for (uint256 i = 0; i < sIds.length; i++) {
            uint8 sId = sIds[i];
            shares = _as.getShares(eIds, sId);
            for (uint256 j = 0; j < shares.length; ++j) {
                shares[j] = Math.mulShr(shares[j], 1e9, 32, Math.Rounding.Ceil);
            }

            emit log_named_array(
                string(abi.encodePacked("Entities (Operators) shares for strategy ", vm.toString(sId))), shares
            );
        }
    }

    function test_UpdateOperators() public {
        _as.mock_init();
        _as.mock_addEntities();

        (uint256[] memory eIds, uint8[] memory cIds, uint8[] memory sIds) = _as.getIds();
        uint256[] memory shares;

        // log metric values
        for (uint256 i = 0; i < eIds.length; i++) {
            uint256 eId = eIds[i];
            uint16[] memory vals = _as.getMetricValues(eId);

            for (uint256 j = 0; j < cIds.length; ++j) {
                if (j == uint8(ASMockValMart.Metrics.Fee)) {
                    vals[j] = ASConvertor._unConvertFee(vals[j]);
                } else if (j == uint8(ASMockValMart.Metrics.Technology)) {
                    vals[j] = ASConvertor._unConvertTech(vals[j]);
                } else if (j == uint8(ASMockValMart.Metrics.Performance)) {
                    vals[j] = ASConvertor._unConvertPerf(vals[j]);
                }
            }

            emit log_named_array(
                string(abi.encodePacked("Metric values for entity ", vm.toString(eId))), convertArrUint16toUint256(vals)
            );
        }

        // log shares
        for (uint256 i = 0; i < sIds.length; i++) {
            uint8 sId = sIds[i];
            shares = _as.getShares(eIds, sId);
            for (uint256 j = 0; j < shares.length; ++j) {
                shares[j] = Math.mulShr(shares[j], 1e9, 32, Math.Rounding.Ceil);
            }

            emit log_named_array(string(abi.encodePacked("Entities shares for strategy ", vm.toString(sId))), shares);
        }

        // update metrics
        uint8 cId = uint8(ASMockValMart.Metrics.Fee);
        uint16[] memory fees = generateVals(eIds.length, ASConvertor.FEE_MIN + 50, ASConvertor.FEE_MAX, 50);
        _as.updateValuesSingleMetric(eIds, cId, fees);

        // log metric values
        for (uint256 i = 0; i < eIds.length; i++) {
            uint256 eId = eIds[i];
            uint16[] memory vals = _as.getMetricValues(eId);

            for (uint256 j = 0; j < cIds.length; ++j) {
                if (j == uint8(ASMockValMart.Metrics.Fee)) {
                    vals[j] = ASConvertor._unConvertFee(vals[j]);
                } else if (j == uint8(ASMockValMart.Metrics.Technology)) {
                    vals[j] = ASConvertor._unConvertTech(vals[j]);
                } else if (j == uint8(ASMockValMart.Metrics.Performance)) {
                    vals[j] = ASConvertor._unConvertPerf(vals[j]);
                }
            }

            emit log_named_array(
                string(abi.encodePacked("Metric new values for entity ", vm.toString(eId))), convertArrUint16toUint256(vals)
            );
        }

        // log shares
        for (uint256 i = 0; i < sIds.length; i++) {
            uint8 sId = sIds[i];
            shares = _as.getShares(eIds, sId);
            for (uint256 j = 0; j < shares.length; ++j) {
                shares[j] = Math.mulShr(shares[j], 1e9, 32, Math.Rounding.Ceil);
            }

            emit log_named_array(
                string(abi.encodePacked("Entities new shares for strategy ", vm.toString(sId))), shares
            );
        }
    }

    struct PrepData {
        uint256[] eIds;
        uint16[] fees;
        uint16[] techs;
        uint16[] perfs;
    }

    function _prep1KEntities(uint256 n) internal returns (PrepData memory d) {
        vm.pauseGasMetering(); // skip gas metering for adding
        _as.mock_init();

        if (n == 0) n = 10000;

        d.eIds = new uint256[](n);
        for (uint256 j = 0; j < n; ++j) {
            d.eIds[j] = j + 1;
        }

        // vm.startSnapshotGas("addEntities");
        _as.addEntitiesNoValues(d.eIds);
        // gasUsed = vm.stopSnapshotGas();
        // console2.log(" Add entities GAS: %d, last ID: %d-%d", gasUsed, i+1, i+B);

        // fees
        d.fees = generateVals(n, ASConvertor.FEE_MIN + 50, ASConvertor.FEE_MAX, 50);
        // techs
        d.techs = generateVals(n, ASConvertor.TECH_VANILLA, ASConvertor.TECH_DVT, 1);
        // perf
        d.perfs = generateVals(n, ASConvertor.PERF_LOW - 500, ASConvertor.PERF_GOOD + 500, 100);
        vm.resumeGasMetering();
    }

    function test_1KUpdate_SetInitialValuesSingleMetric() public {
        // initial setup of 1000 entities
        PrepData memory d = _prep1KEntities(1000);
        uint256 gasUsed;
        uint256 updCnt;

        /// @dev update fees, 1000 in one pass
        /// @dev count total gas with updates preparation (simulate some real usage)
        vm.startSnapshotGas("initialUpdateSingleMetric");

        updCnt = _as.updateValuesSingleMetric(d.eIds, uint8(ASMockValMart.Metrics.Fee), d.fees);

        gasUsed = vm.stopSnapshotGas();
        console2.log("initialUpdateSingleMetric GAS: %d", gasUsed);

        assertEq(updCnt, 1000, "Unexpected update count");
    }

    function test_1KUpdate_SetInitialValuesBatchMetric() public {
        // initial setup of 1000 entities
        PrepData memory d = _prep1KEntities(1000);

        uint256 gasUsed;
        uint256 updCnt;

        vm.startSnapshotGas("initialUpdateBatchMetric");

        uint8[] memory cIds = new uint8[](2);
        cIds[0] = uint8(ASMockValMart.Metrics.Technology);
        cIds[1] = uint8(ASMockValMart.Metrics.Performance);

        uint16[][] memory mVals = new uint16[][](2);
        mVals[0] = d.techs;
        mVals[1] = d.perfs;

        /// @dev updates fee, tech and perfs, 1000 in one pass
        updCnt = _as.updateValues(d.eIds, cIds, mVals);

        gasUsed = vm.stopSnapshotGas();
        console2.log("initialUpdateBatchMetric GAS: %d", gasUsed);

        assertEq(updCnt, 1000, "Unexpected update count");
    }

    function test_1KUpdate_UpdateValuesSingleMetric() public {
        // initial setup of 1000 entities
        PrepData memory d = _prep1KEntities(1000);

        uint256 gasUsed;
        uint256 updCnt;

        // skip gas metering for initial metrics setup
        vm.pauseGasMetering();
        _as.updateValuesSingleMetric(d.eIds, uint8(ASMockValMart.Metrics.Performance), d.perfs);
        vm.roll(block.number + 1);

        // regenerate new values for perf metric
        uint16[] memory newPerfs = generateVals(1000, ASConvertor.PERF_LOW - 500, ASConvertor.PERF_GOOD + 500, 100);

        /// @dev note to converting values, due to that actual updated count in contract might be less of changed values
        uint256 changeCount;
        for (uint256 i = 0; i < d.perfs.length; i++) {
            if (ASConvertor._convertPerf(d.perfs[i]) != ASConvertor._convertPerf(newPerfs[i])) {
                changeCount++;
            }
        }

        vm.resumeGasMetering();
        vm.startSnapshotGas("updateSingleMetric");

        /// @dev  update perfs, 1000 in one pass
        updCnt = _as.updateValuesSingleMetric(d.eIds, uint8(ASMockValMart.Metrics.Performance), newPerfs);

        gasUsed = vm.stopSnapshotGas();
        vm.pauseGasMetering();
        console2.log("updateSingleMetric GAS: %d", gasUsed);

        assertEq(updCnt, changeCount, "Unexpected update count");
    }

    function test_1KUpdate_UpdateValuesBatchMetric() public {
        PrepData memory d = _prep1KEntities(1000);

        uint256 gasUsed;
        uint256 updCnt;

        // skip gas metering for initial metrics setup
        vm.pauseGasMetering();

        uint8[] memory cIds = new uint8[](3);
        cIds[0] = uint8(ASMockValMart.Metrics.Technology);
        cIds[1] = uint8(ASMockValMart.Metrics.Performance);
        cIds[2] = uint8(ASMockValMart.Metrics.Fee);

        uint16[][] memory mVals = new uint16[][](3);
        mVals[0] = d.techs;
        mVals[1] = d.perfs;
        mVals[2] = d.fees;

        /// @dev updates fee, tech and perfs, 1000 in one pass
        _as.updateValues(d.eIds, cIds, mVals);

        // regenerate new values for perf metric
        uint16[] memory newFees = generateVals(1000, ASConvertor.FEE_MIN + 50, ASConvertor.FEE_MAX, 50);
        uint16[] memory newPerfs = generateVals(1000, ASConvertor.PERF_LOW - 500, ASConvertor.PERF_GOOD + 500, 100);

        /// @dev note to converting values, due to that actual updated count in contract might be less of changed values
        uint256 changeCount;
        for (uint256 i = 0; i < d.perfs.length; i++) {
            if (
                ASConvertor._convertPerf(d.perfs[i]) != ASConvertor._convertPerf(newPerfs[i])
                    || ASConvertor._convertFee(d.fees[i]) != ASConvertor._convertFee(newFees[i])
            ) {
                changeCount++;
            }
        }

        vm.resumeGasMetering();
        vm.startSnapshotGas("updateBatchMetric");

        /// @dev update fees+perfs, 1000 in one pass
        /// @dev count total gas with updates preparation (simulate some real usage)

        cIds = new uint8[](2);
        cIds[0] = uint8(ASMockValMart.Metrics.Fee);
        cIds[1] = uint8(ASMockValMart.Metrics.Performance);

        mVals = new uint16[][](2);
        mVals[0] = newFees;
        mVals[1] = newPerfs;

        updCnt = _as.updateValues(d.eIds, cIds, mVals);
        gasUsed = vm.stopSnapshotGas();
        vm.pauseGasMetering();
        console2.log("updateBatchMetric GAS: %d", gasUsed);

        assertEq(updCnt, changeCount, "Unexpected update count");
    }
}
