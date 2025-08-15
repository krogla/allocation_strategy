// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {ASCore} from "./lib/as/ASCore.sol";
import {ASMockBase, MockData, MockDataEntity, MockDataStrategy, MockDataMetric} from "./ASMockBase.sol";
import {ASConvertor} from "./lib/as/ASConvertor.sol";

// import {console2} from "forge-std/console2.sol";

contract ASMockValMart is ASMockBase {
    using ASCore for bytes32;

    enum Metrics {
        Fee,
        Technology,
        Performance
    }

    constructor() {
        AS_STORAGE = keccak256(abi.encode(uint256(keccak256(abi.encodePacked("AS.storage.operators"))) - 1))
            & ~bytes32(uint256(0xff));
    }

    function _mockData() internal pure override returns (MockData memory d) {
        uint256[] memory eIds = new uint256[](5);
        eIds[0] = 11;
        eIds[1] = 22;
        eIds[2] = 33;
        eIds[3] = 44;
        eIds[4] = 55;

        d.entities = new MockDataEntity[](eIds.length);
        d.entities[0] = MockDataEntity({id: eIds[0], description: "Op 1"});
        d.entities[1] = MockDataEntity({id: eIds[1], description: "Op 2"});
        d.entities[2] = MockDataEntity({id: eIds[2], description: "Op 3"});
        d.entities[3] = MockDataEntity({id: eIds[3], description: "Op 4"});
        d.entities[4] = MockDataEntity({id: eIds[4], description: "Op 5"});

        assert(uint8(Metrics.Fee) == 0);
        assert(uint8(Metrics.Technology) == 1);
        assert(uint8(Metrics.Performance) == 2);

        uint8[] memory cIds = new uint8[](3);
        cIds[0] = 0; //uint8(Metrics.Fee);
        cIds[1] = 1; //uint8(Metrics.Technology);
        cIds[2] = 2; //uint8(Metrics.Performance);

        d.metrics = new MockDataMetric[](cIds.length);

        d.metrics[0] =
            MockDataMetric({id: 0, description: "Fee", defWeight: 0, mValues: new uint16[](eIds.length)});
        d.metrics[0].mValues[0] = 50; // 0.50%
        d.metrics[0].mValues[1] = 250; // 2.50%
        d.metrics[0].mValues[2] = 200; // 2.00%
        d.metrics[0].mValues[3] = 500; // 5.00%
        d.metrics[0].mValues[4] = 350; // 3.50%

        d.metrics[1] =
            MockDataMetric({id: 1, description: "Technology", defWeight: 0, mValues: new uint16[](eIds.length)});
        d.metrics[1].mValues[0] = ASConvertor.TECH_DVT;
        d.metrics[1].mValues[1] = ASConvertor.TECH_VANILLA;
        d.metrics[1].mValues[2] = ASConvertor.TECH_DVT;
        d.metrics[1].mValues[3] = ASConvertor.TECH_VANILLA;
        d.metrics[1].mValues[4] = ASConvertor.TECH_VANILLA;

        d.metrics[2] =
            MockDataMetric({id: 2, description: "Performance", defWeight: 0, mValues: new uint16[](eIds.length)});
        d.metrics[2].mValues[0] = 9600; // 96%
        d.metrics[2].mValues[1] = 9700; // 97%
        d.metrics[2].mValues[2] = 9000; // 90%
        d.metrics[2].mValues[3] = 8700; // 87%
        d.metrics[2].mValues[4] = 8000; // 80%

        assert(uint8(Strategies.Deposit) == 0);
        assert(uint8(Strategies.Withdrawal) == 1);
        uint8[] memory sIds = new uint8[](2);
        sIds[0] = 0; // uint8(Strategies.Deposit);
        sIds[1] = 1; // uint8(Strategies.Withdrawal);

        d.strategies = new MockDataStrategy[](sIds.length);

        d.strategies[0] =
            MockDataStrategy({id: 0, description: "Deposit", cIds: cIds, cWeights: new uint16[](cIds.length)});
        // metrics weights for Deposit strategy
        d.strategies[0].cWeights[0] = 50000;
        d.strategies[0].cWeights[1] = 20000;
        d.strategies[0].cWeights[2] = 30000;

        d.strategies[1] =
            MockDataStrategy({id: 1, description: "Withdrawal", cIds: cIds, cWeights: new uint16[](cIds.length)});
        // metrics weights for Withdrawal strategy
        d.strategies[1].cWeights[0] = 40000;
        d.strategies[1].cWeights[1] = 30000;
        d.strategies[1].cWeights[2] = 30000;
    }

    function _convertorInput(uint16[] memory vals, uint8 cId) internal pure override returns (uint16[] memory) {
        if (cId == uint8(Metrics.Fee)) {
            return ASConvertor._convertFees(vals);
        } else if (cId == uint8(Metrics.Technology)) {
            return ASConvertor._convertTechs(vals);
        } else if (cId == uint8(Metrics.Performance)) {
            return ASConvertor._convertPerfs(vals);
        }
        return vals;
    }
}
