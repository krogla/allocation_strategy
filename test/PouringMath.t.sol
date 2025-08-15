// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {ASCommon} from "./helpers/ASCommon.sol";
import {PouringMath} from "../src/lib/as/PouringMath.sol";

contract PouringMathTest is ASCommon {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_FillDepositImbalance() public {
        uint256[] memory shares = new uint256[](2);
        shares[0] = (uint256(50_00) << 32) / 10000; // 50% in Q32.32
        shares[1] = (uint256(50_00) << 32) / 10000; // 50% in Q32.32

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;
        uint256[] memory capacities = new uint256[](2);
        capacities[0] = 100;
        capacities[1] = 40;

        uint256 total = amounts[0] + amounts[1];
        uint256 inflow = 90; // total inflow

        // new total = 0 + 90 = 90
        // target[0] = min(100, 50% * 90) = min(100, 45) = 45
        // target[1] = min(40, 50% * 90) = min(40, 45) = 40
        // left = 90 - (45 + 40) = 5

        (uint256[] memory imbalance, uint256[] memory fills, uint256 rest) =
            PouringMath._allocate(shares, amounts, capacities, total, inflow);
        emit log_named_array("fills", fills);
        emit log_named_array("imbalance", imbalance);

        assertEq(fills[0], 45); // до ideal-capacity не доходит
        assertEq(fills[1], 40); // упёрлись ровно в cap
        assertEq(rest, 5); // остаток не ушёл никуда
    }

    /// rubber bucket (tgt = 100 %) получает остаток
    function testDeposit_RubberBucketAbsorbsRemainder() public {
        uint256[] memory shares = new uint256[](3);
        shares[0] = (uint256(30_00) << 32) / 10000; // 30% in Q32.32
        shares[1] = 0; //(uint256(0_00) << 32) / 10000; // 0%,skip
        shares[2] = (uint256(70_00) << 32) / 10000; // rubber, 70%

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 30;
        amounts[1] = 0;
        amounts[2] = 0;
        uint256[] memory capacities = new uint256[](3);
        capacities[0] = 1000;
        capacities[1] = 1000;
        capacities[2] = 1000;

        uint256 total = amounts[0] + amounts[1] + amounts[2];
        uint256 inflow = 70; // total inflow
        // new total = 30 + 70 = 100
        // ideal[0] = min(1000, 30% * 100) = min(1000, 30) = 30 - 30 = 0
        // ideal[1] = skip
        // ideal[2] = min(1000, 100% * 70) = min(1000, 70) = 70
        // left = 0 (т.е. всё ушло в 3-ю корзину)

        (uint256[] memory imbalance, uint256[] memory fills, uint256 rest) =
            PouringMath._allocate(shares, amounts, capacities, total, inflow);
        emit log_named_array("fills", fills);
        emit log_named_array("imbalance", imbalance);

        assertEq(fills[0], 0); // до ideal-capacity не доходит
        assertEq(fills[1], 0);
        assertEq(fills[2], 70);
        assertEq(rest, 0); // остаток не ушёл никуда
    }

    function test_FillWithdrawalImbalance() public {
        // uint256[] memory sharesIn = new uint256[](3);
        // sharesIn[0] = (uint256(94_00) << 32) / 10000; // 94% in Q32.32
        // sharesIn[1] = (uint256(4_00) << 32) / 10000; // 4% in Q32.32
        // sharesIn[2] = (uint256(2_00) << 32) / 10000; // 2% in Q32.32

        uint256[] memory sharesOut = new uint256[](3);
        sharesOut[0] = (uint256(93_06) << 32) / 10000; // 93.06% in Q32.32
        sharesOut[1] = (uint256(4_44) << 32) / 10000; // 4.44% in Q32.32
        sharesOut[2] = (uint256(2_50) << 32) / 10000; // 2.5% in Q32.32

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 110_000;
        amounts[1] = 3_000;
        amounts[2] = 3_000;

        // uint256[] memory capacities = new uint256[](3);
        // capacities[0] = 200_000;
        // capacities[1] = 10_000;
        // capacities[2] = 10_000;

        uint256 total = amounts[0] + amounts[1] + amounts[2];
        // uint256 inflow = 1600; // total inflow
        uint256 outflow = 2000; // total outflow

        // new total = 110_000 + 3_000 + 3_000 = 116_000 - 2000 = 114_000
        // target[0] = 93.06% * 114000 = 106088
        // target[1] = 4.44% * 114000 = 5061
        // target[2] = 2.50% * 114000 = 2850
        // rest = 0 (т.е. всё ушло в 1-ю корзину)

        (uint256[] memory imbalance, uint256[] memory fills, uint256 rest) =
            PouringMath._deallocate(sharesOut, amounts, total, outflow);
        emit log_named_array("fills after", fills);
        emit log_named_array("imbalance after", imbalance);

        // console.log("rest = %d", rest);
        assertEq(fills[0], 2000); // до ideal-capacity не доходит
        assertEq(fills[1], 0);
        assertEq(fills[2], 0);
        assertEq(rest, 0); // остатка нет
    }
}
