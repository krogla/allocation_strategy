// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {ASCore} from "./lib/as/ASCore.sol";
import {ASMockBase, MockData, MockDataEntity, MockDataStrategy, MockDataMetric} from "./ASMockBase.sol";
import {ASConvertor} from "./lib/as/ASConvertor.sol";

// import {console2} from "forge-std/console2.sol";

contract ASMockSR is ASMockBase {
    using ASCore for bytes32;

    enum Metrics {
        DepositTargetShare,
        WithdrawalProtectShare
    }

    constructor() {
        AS_STORAGE = keccak256(abi.encode(uint256(keccak256(abi.encodePacked("AS.storage.modules"))) - 1))
            & ~bytes32(uint256(0xff));
    }

    function _mockData() internal pure override returns (MockData memory d) {
        uint256[] memory eIds = new uint256[](3);
        eIds[0] = 1; // aka Curated
        eIds[1] = 2; // aka SDVT
        eIds[2] = 3; // aka CSM

        d.entities = new MockDataEntity[](eIds.length);
        d.entities[0] = MockDataEntity({id: eIds[0], description: "Curated"});
        d.entities[1] = MockDataEntity({id: eIds[1], description: "SDVT"});
        d.entities[2] = MockDataEntity({id: eIds[2], description: "CSM"});

        assert(uint8(Metrics.DepositTargetShare) == 0);
        assert(uint8(Metrics.WithdrawalProtectShare) == 1);
        uint8[] memory cIds = new uint8[](2);
        cIds[0] = 0; //uint8(Metrics.DepositTargetShare);
        cIds[1] = 1; //uint8(Metrics.WithdrawalProtectShare);

        d.metrics = new MockDataMetric[](cIds.length);

        d.metrics[0] = MockDataMetric({
            id: 0,
            description: "Deposit TargetShare",
            defWeight: 50000,
            mValues: new uint16[](eIds.length)
        });
        d.metrics[0].mValues[0] = 10000; // Curated target share
        d.metrics[0].mValues[1] = 400; // SDVT target share
        d.metrics[0].mValues[2] = 300; // CSM target share

        d.metrics[1] = MockDataMetric({
            id: 1,
            description: "Withdrawal ProtectShare",
            defWeight: 50000,
            mValues: new uint16[](eIds.length)
        });
        d.metrics[1].mValues[0] = 10000; // Curated withdrawal threshold
        d.metrics[1].mValues[1] = 444; // SDVT withdrawal threshold
        d.metrics[1].mValues[2] = 375; // CSM withdrawal threshold

        assert(uint8(Strategies.Deposit) == 0);
        assert(uint8(Strategies.Withdrawal) == 1);
        uint8[] memory sIds = new uint8[](2);
        sIds[0] = 0; // uint8(Strategies.Deposit);
        sIds[1] = 1; // uint8(Strategies.Withdrawal);

        d.strategies = new MockDataStrategy[](sIds.length);

        d.strategies[0] =
            MockDataStrategy({id: 0, description: "Deposit", cIds: cIds, cWeights: new uint16[](cIds.length)});
        // metrics weights for Deposit strategy
        // TargetShare (relative weight 100%), ProtectShare (relative weight 0%)
        d.strategies[0].cWeights[0] = 50000;
        d.strategies[0].cWeights[1] = 0;

        d.strategies[1] =
            MockDataStrategy({id: 1, description: "Withdrawal", cIds: cIds, cWeights: new uint16[](cIds.length)});
        // metrics weights for Withdrawal strategy
        // TargetShare (relative weight 0%), ProtectShare (relative weight 100%)
        d.strategies[1].cWeights[0] = 0;
        d.strategies[1].cWeights[1] = 50000;
    }

    function _convertorInput(uint16[] memory vals, uint8) internal pure override returns (uint16[] memory) {
        return ASConvertor._rescaleBps(vals);
    }
}
