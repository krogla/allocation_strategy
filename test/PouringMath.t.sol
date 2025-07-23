// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {ASCommon} from "./helpers/ASCommon.sol";
import {PouringMath, BasketCache} from "../src/lib/PouringMath.sol";

contract PouringMathTest is ASCommon {
    using PouringMath for BasketCache[];

    /* helpers */
    function _one(uint256 amt, uint256 cap, uint256 tgt, uint256 ptc) internal pure returns (BasketCache memory b) {
        b.amount = amt;
        b.capacity = cap;
        b.targetBps = tgt;
        b.protectBps = ptc;
    }

    function setUp() public virtual override {
        super.setUp();
        // als = new AllocationStrategy();
    }

    /*──────────────────── DEPOSIT ────────────────────*/

    /// simple 50/50 fill until one hits capacity
    function testDeposit_WaterFillStopsOnCapacity() public pure{
        BasketCache[] memory bs = new BasketCache[](2);
        bs[0] = _one(0, 100, 50_00, 0); // ideal 50
        bs[1] = _one(0, 40, 50_00, 0); // ideal 40 (limited)

        uint inflow = 90; // total inflow

        // new total = 0 + 90 = 90
        // ideal[0] = min(100, 50% * 90) = min(100, 45) = 45
        // ideal[1] = min(40, 50% * 90) = min(40, 45) = 40
        // left = 90 - (45 + 40) = 5

        (uint256[] memory got, uint left) = bs.computeDeposits(inflow);
        assertEq(got[0], 45); // до ideal-capacity не доходит
        assertEq(got[1], 40); // упёрлись ровно в cap
        assertEq(left, 5); // остаток не ушёл никуда
    }

    /// rubber bucket (tgt = 100 %) получает остаток
    function testDeposit_RubberBucketAbsorbsRemainder() public pure {
        BasketCache[] memory bs = new BasketCache[](3);
        bs[0] = _one(30, 1_000, 30_00, 0); // needs  0
        bs[1] = _one(0, 1_000, 0, 0); // black hole, skip
        bs[2] = _one(0, 1_000, 100_00, 0); // rubber

        uint inflow = 70; // total inflow
        // new total = 30 + 70 = 100
        // ideal[0] = min(1000, 30% * 100) = min(1000, 50) = 30
        // ideal[1] = skip
        // ideal[2] = min(1000, 100% * 100) = min(1000, 100) = 100
        // left = 0 (т.е. всё ушло в 2-ю корзину)

        (uint256[] memory got, uint left) = bs.computeDeposits(inflow);
        assertEq(got[0], 0);
        assertEq(got[1], 0);
        assertEq(got[2], 70); // всё ушло сюда
        assertEq(left, 0); // остатка нет

    }

    function testDeposit_Withdraw() public pure {
        BasketCache[] memory bs = new BasketCache[](3);
        bs[0] = _one(110_000, 200_000, 100_00, 0);
        bs[1] = _one(3_000, 10_000, 4_00, 4_44);
        bs[2] = _one(2_300, 10_000, 2_00, 2_50);

        uint inflow = 1600; // total inflow
        uint outflow = 20000; // total inflow
        // new total = 30 + 70 = 100
        // ideal[0] = min(1000, 30% * 100) = min(1000, 50) = 30
        // ideal[1] = skip
        // ideal[2] = min(1000, 100% * 100) = min(1000, 100) = 100
        // left = 0 (т.е. всё ушло в 2-ю корзину)

        (uint256[] memory got, uint leftIn) = bs.computeDeposits(inflow);
        (uint256[] memory take, uint leftOut) = bs.computeWithdrawals(outflow);

        console.log("got[0] = %s, got[1] = %s, got[2] = %s", got[0], got[1], got[2]);
        console.log("leftIn = %s", leftIn);
        console.log("take[0] = %s, take[1] = %s, take[2] = %s", take[0], take[1], take[2]);
        console.log("leftOut = %s", leftOut);
        // console.log("got[0] = %s, got[1] = %s, got[2] = %s, left = %s", got[0], got[1], got[2], left);
        // assertEq(got[0], 0);
        // assertEq(got[1], 0);
        // assertEq(got[2], 70); // всё ушло сюда
        // assertEq(left, 0); // остатка нет

    }

}
