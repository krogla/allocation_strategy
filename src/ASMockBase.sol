// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {ASCore} from "./lib/as/ASCore.sol";
import {PouringMath} from "./lib/as/PouringMath.sol";

// import {console2} from "forge-std/console2.sol";

struct MockDataEntity {
    uint256 id;
    string description;
}

struct MockDataStrategy {
    uint8 id;
    string description;
    uint8[] cIds;
    uint16[] cWeights;
}

struct MockDataMetric {
    uint8 id;
    uint16 defWeight;
    string description;
    uint16[] mValues; //  per entity
}

struct MockData {
    MockDataEntity[] entities;
    MockDataStrategy[] strategies;
    MockDataMetric[] metrics;
}

abstract contract ASMockBase {
    using ASCore for bytes32;

    enum Strategies {
        Deposit,
        Withdrawal,
        Reward
    }

    bytes32 internal immutable AS_STORAGE;

    // initialize metrics and strategies
    function mock_init() public {
        MockData memory d = _mockData();
        // add metrics
        MockDataMetric memory c;
        for (uint256 i = 0; i < d.metrics.length; i++) {
            c = d.metrics[i];
            AS_STORAGE.enableMetric(c.id, c.defWeight, c.description);
        }

        // add strategies
        MockDataStrategy memory s;
        for (uint256 i = 0; i < d.strategies.length; i++) {
            s = d.strategies[i];
            AS_STORAGE.enableStrategy(s.id, s.description);
            // set metric weights for strategy
            AS_STORAGE.setWeights(s.id, s.cIds, s.cWeights);
        }
    }

    // add entities with metric values
    function mock_addEntities() public returns (uint256 updCnt) {
        MockData memory d = _mockData();
        uint256[] memory eIds = new uint256[](d.entities.length);
        uint8[] memory cIds = new uint8[](d.metrics.length);

        uint16[][] memory newVals = new uint16[][](eIds.length);
        for (uint256 i = 0; i < eIds.length; i++) {
            eIds[i] = d.entities[i].id;
            newVals[i] = new uint16[](cIds.length);
        }

        MockDataMetric memory c;
        for (uint256 i = 0; i < cIds.length; i++) {
            c = d.metrics[i];
            cIds[i] = c.id;
            uint16[] memory vals = _convertorInput(c.mValues, c.id);
            for (uint256 j = 0; j < eIds.length; j++) {
                newVals[j][i] = vals[j];
            }
        }

        return AS_STORAGE.addEntities(eIds, cIds, newVals);
    }

    /// @notice Add entities
    function addEntitiesNoValues(uint256[] memory eIds) public returns (uint256 updCnt) {
        return addEntities(eIds, new uint8[](0), new uint16[][](0));
    }

    function addEntities(uint256[] memory eIds, uint8[] memory cIds, uint16[][] memory vals)
        public
        returns (uint256 updCnt)
    {
        return AS_STORAGE.addEntities(eIds, cIds, vals);
    }

    /// @notice Update metric values for entities
    function updateValuesSingleMetric(uint256[] memory eIds, uint8 cId, uint16[] memory vals)
        public
        returns (uint256 updCnt)
    {
        uint16[][] memory mVals = new uint16[][](1);
        uint8[] memory cIds = new uint8[](1);
        cIds[0] = cId;
        mVals[0] = vals;

        return updateValues(eIds, cIds, mVals);
    }

    function updateValues(uint256[] memory eIds, uint8[] memory cIds, uint16[][] memory mVals)
        public
        returns (uint256 updCnt)
    {
        uint256 eCnt = eIds.length;
        uint256 cCnt = cIds.length;
        uint16[][] memory newVals = new uint16[][](eCnt);

        // console2.log("entities: %", eIds.length);
        // console2.log("categories: %", cIds.length);
        // console2.log("values: %", mVals.length);
        // console2.log("values: %", mVals[0].length);
        for (uint256 i = 0; i < eCnt; i++) {
            newVals[i] = new uint16[](cCnt);
        }

        // apply values conversion
        for (uint256 i = 0; i < cCnt; i++) {
            uint8 cId = cIds[i];
            // console2.log("cId: %", cId);
            uint16[] memory vals = _convertorInput(mVals[i], cId);
            // console2.log("vals: %", vals.length);
            for (uint256 j = 0; j < eIds.length; j++) {
                newVals[j][i] = vals[j];
            }
        }

        return AS_STORAGE.batchUpdate(eIds, cIds, newVals);
    }

    /// @notice Get Allocation for Deposits
    function getAllocation(
        uint256[] memory eIds,
        uint256[] memory amounts,
        uint256[] memory capacities,
        uint256 totalAmount,
        uint256 inflow
    ) public view returns (uint256[] memory imbalance, uint256[] memory fills, uint256 rest) {
        // get entity's shares
        uint8 sId = uint8(Strategies.Deposit);
        uint256[] memory shares = AS_STORAGE.sharesOf(eIds, sId);
        (imbalance, fills, rest) = PouringMath._allocate(shares, amounts, capacities, totalAmount, inflow);
    }

    /// @notice Get (De)Allocation for Withdrawals
    function getDeallocation(uint256[] memory eIds, uint256[] memory amounts, uint256 totalAmount, uint256 outflow)
        public
        view
        returns (uint256[] memory imbalance, uint256[] memory fills, uint256 rest)
    {
        // get entity's shares
        uint8 sId = uint8(Strategies.Withdrawal);
        uint256[] memory shares = AS_STORAGE.sharesOf(eIds, sId);
        (imbalance, fills, rest) = PouringMath._deallocate(shares, amounts, totalAmount, outflow);
    }

    function getStrategies() public view returns (ASCore.Strategy[] memory strategies) {
        uint8[] memory sIds = AS_STORAGE.getEnabledStrategies();
        strategies = new ASCore.Strategy[](sIds.length);
        for (uint256 i = 0; i < sIds.length; i++) {
            strategies[i] = AS_STORAGE._getStrategyRaw(sIds[i]);
        }
    }

    function getMetrics() public view returns (ASCore.Metric[] memory metrics) {
        uint8[] memory cIds = AS_STORAGE.getEnabledMetrics();
        metrics = new ASCore.Metric[](cIds.length);
        for (uint256 i = 0; i < cIds.length; i++) {
            metrics[i] = AS_STORAGE._getMetricRaw(cIds[i]);
        }
    }

    function getEntities() public view returns (uint256[] memory eIds) {
        return AS_STORAGE.getEntities();
    }

    /// @notice Get all IDs for entities, metrics, and strategies
    function getIds() public view returns (uint256[] memory eIds, uint8[] memory cIds, uint8[] memory sIds) {
        return (AS_STORAGE.getEntities(), AS_STORAGE.getEnabledMetrics(), AS_STORAGE.getEnabledStrategies());
    }

    /// @notice Get shares of entities for a specific strategy
    function getShares(uint256[] memory eIds, uint8 sId) public view returns (uint256[] memory) {
        return AS_STORAGE.sharesOf(eIds, sId);
    }

    function getMetricValues(uint256 eId) public view returns (uint16[] memory) {
        return AS_STORAGE.getMetricValues(eId);
    }

    // ### INTERNALS ###

    function _mockData() internal pure virtual returns (MockData memory d) {
        d.entities = new MockDataEntity[](0);
        d.metrics = new MockDataMetric[](0);
        d.strategies = new MockDataStrategy[](0);
    }

    // values -> raw AS values
    /// @dev override if needed
    function _convertorInput(uint16[] memory vals, uint8 cId) internal pure virtual returns (uint16[] memory) {
        cId;
        return vals;
    }
}
