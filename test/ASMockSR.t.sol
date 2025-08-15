// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ASCommon} from "./helpers/ASCommon.sol";
import {ASCore} from "../src/lib/as/ASCore.sol";
import {ASMockSR} from "../src/ASMockSR.sol";

import {console2} from "forge-std/console2.sol";

contract ASTest is ASCommon {
    using ASCore for bytes32;

    ASMockSR public _as;

    function setUp() public virtual override {
        super.setUp();
        _as = new ASMockSR();
    }

    function test_AddMetricsAndStrategies() public {
        _as.mock_init();

        (, uint8[] memory cIds, uint8[] memory sIds) = _as.getIds();
        assertEq(sIds.length, 2, "Strategies (Modules) count mismatch");
        assertEq(cIds.length, 2, "Metrics (Modules) count mismatch");

        emit log_named_array("Strategies (Modules)", convertArrUint8toUint256(sIds));
        emit log_named_array("Metrics (Modules)", convertArrUint8toUint256(cIds));
    }

    function test_AddEntities() public {
        _as.mock_init();
        _as.mock_addEntities();

        (uint256[] memory eIds,, uint8[] memory sIds) = _as.getIds();

        assertEq(eIds.length, 3, "Entities (Modules) count mismatch");
        emit log_named_array("Entities (Modules)", eIds);

        uint256[] memory shares;
        for (uint256 i = 0; i < sIds.length; i++) {
            uint8 sId = sIds[i];
            shares = _as.getShares(eIds, sId);
            for (uint256 j = 0; j < shares.length; ++j) {
                shares[j] = Math.mulShr(shares[j], 1e9, 32, Math.Rounding.Ceil);
            }

            emit log_named_array(
                string(abi.encodePacked("Entities (Modules) shares for strategy ", vm.toString(sId))), shares
            );
        }
    }

    function test_AllocateModules() public {
        _as.mock_init();
        _as.mock_addEntities();

        (uint256[] memory eIds,,) = _as.getIds();
        uint256[] memory amounts = new uint256[](eIds.length);
        amounts[0] = 1_000_000;
        amounts[1] = 30_000;
        amounts[2] = 20_000;
        uint256[] memory capacities = new uint256[](eIds.length);
        capacities[0] = 50_000;
        capacities[1] = 22_500;
        capacities[2] = 15_000;
        // (amounts, capacities) = _as.getAllocations(eIds);

        uint256 totalAmount = amounts[0] + amounts[1] + amounts[2];
        uint256 inflow = 10_000;

        uint256 gasBefore = gasleft();
        (uint256[] memory imbalance, uint256[] memory fills, uint256 rest) =
            _as.getAllocation(eIds, amounts, capacities, totalAmount, inflow);
        uint256 gasAfter = gasleft();
        // console2.log("Rest:", rest);
        // emit log_named_array("fills", fills);
        // emit log_named_array("imbalance", imbalance);

        assertEq(fills[0], 0);
        assertEq(fills[1], 5300);
        assertEq(fills[2], 4700);
        assertEq(imbalance[0], 0);
        assertEq(imbalance[1], 7100);
        assertEq(imbalance[2], 7100);
        assertEq(rest, 0);

        console2.log("Gas usage Allocate modules: %d", gasBefore - gasAfter);
    }

    function test_DeAllocateModules() public {
        _as.mock_init();
        _as.mock_addEntities();

        (uint256[] memory eIds,,) = _as.getIds();
        uint256[] memory amounts = new uint256[](eIds.length);
        amounts[0] = 100_000;
        amounts[1] = 30_000;
        amounts[2] = 20_000;
        uint256[] memory capacities = new uint256[](eIds.length);
        capacities[0] = 50_000;
        capacities[1] = 22_500;
        capacities[2] = 15_000;
        // (amounts, capacities) = _as.getAllocations(eIds);

        uint256 totalAmount = amounts[0] + amounts[1] + amounts[2];
        uint256 outflow = 10_000;

        uint256 gasBefore = gasleft();
        (uint256[] memory imbalance, uint256[] memory fills, uint256 rest) =
            _as.getDeallocation(eIds, amounts, totalAmount, outflow);
        uint256 gasAfter = gasleft();
        // console2.log("Rest:", rest);
        // emit log_named_array("fills", fills);
        // emit log_named_array("imbalance", imbalance);

        assertEq(fills[0], 0);
        assertEq(fills[1], 9517);
        assertEq(fills[2], 483);
        assertEq(imbalance[0], 0);
        assertEq(imbalance[1], 14267);
        assertEq(imbalance[2], 14267);
        assertEq(rest, 0);

        console2.log("Gas usage Deallocate modules: %d", gasBefore - gasAfter);
    }
}
