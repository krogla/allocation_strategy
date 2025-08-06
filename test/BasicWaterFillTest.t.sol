// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {WaterFillOptimized} from "../src/lib/WaterFill1.sol";
import {WaterFillNoSort} from "../src/lib/WaterFill2.sol";

/// @title Basic Water Fill Algorithm Comparison
contract BasicWaterFillTest is Test {
    WaterFillOptimized public waterFill1;
    WaterFillNoSort public waterFill2;

    function setUp() public {
        waterFill1 = new WaterFillOptimized();
        waterFill2 = new WaterFillNoSort();
    }

    /// @notice Test correctness with small arrays
    function testCorrectness() public {
        uint256[] memory targets = new uint256[](5);
        targets[0] = 1000;
        targets[1] = 2000;
        targets[2] = 1500;
        targets[3] = 3000;
        targets[4] = 500;

        uint256 inflow = 4000;

        (uint256[] memory fills1, uint256 rest1) = waterFill1.pour(targets, inflow);
        (uint256[] memory fills2, uint256 rest2) = waterFill2.pour(targets, inflow);

        // Both should produce identical results
        assertEq(rest1, rest2, "Rest amounts should match");
        assertEq(fills1.length, fills2.length, "Fill arrays should have same length");

        for (uint256 i = 0; i < fills1.length; i++) {
            assertEq(fills1[i], fills2[i], "Individual fills should match");
        }

        // Verify water fill properties
        uint256 totalFilled = 0;
        for (uint256 i = 0; i < fills1.length; i++) {
            totalFilled += fills1[i];
            assertLe(fills1[i], targets[i], "Fill should not exceed target");
        }

        assertEq(totalFilled + rest1, inflow, "Total should equal inflow");
    }

    /// @notice Test gas efficiency comparison
    function testGasComparison() public {
        // Test different sizes
        _testGasForSize(20);
        _testGasForSize(100);
        _testGasForSize(400);
        _testGasForSize(800);
        _testGasForSize(1000);
    }

    function _testGasForSize(uint256 size) internal {
        uint256[] memory targets = _generateTargets(size);
        uint256 inflow = _sumArray(targets) / 2; // 50% inflow

        // Measure WaterFill1 gas
        uint256 gasBefore1 = gasleft();
        (uint256[] memory fills1, uint256 rest1) = waterFill1.pour(targets, inflow);
        uint256 gasUsed1 = gasBefore1 - gasleft();

        // Measure WaterFill2 gas
        uint256 gasBefore2 = gasleft();
        (uint256[] memory fills2, uint256 rest2) = waterFill2.pour(targets, inflow);
        uint256 gasUsed2 = gasBefore2 - gasleft();

        // Verify correctness
        assertEq(rest1, rest2, "Rest should match");
        assertEq(fills1.length, fills2.length, "Array lengths should match");

        // Results tracking (we can't use console, so we'll use events or assertions)
        if (gasUsed1 < gasUsed2) {
            // WaterFill1 (sorting) is more efficient
            assertTrue(gasUsed1 < gasUsed2);
        } else {
            // WaterFill2 (binary search) is more efficient
            assertTrue(gasUsed2 <= gasUsed1);
        }

        // Emit results for logging
        emit GasComparison(size, gasUsed1, gasUsed2, gasUsed1 < gasUsed2);
    }

    /// @notice Test edge cases
    function testEdgeCases() public {
        // Empty array
        uint256[] memory empty = new uint256[](0);
        (uint256[] memory fills1, uint256 rest1) = waterFill1.pour(empty, 1000);
        (uint256[] memory fills2, uint256 rest2) = waterFill2.pour(empty, 1000);
        assertEq(fills1.length, 0);
        assertEq(fills2.length, 0);
        assertEq(rest1, 1000);
        assertEq(rest2, 1000);

        // Single element
        uint256[] memory single = new uint256[](1);
        single[0] = 500;
        (fills1, rest1) = waterFill1.pour(single, 300);
        (fills2, rest2) = waterFill2.pour(single, 300);
        assertEq(fills1[0], 300);
        assertEq(fills2[0], 300);
        assertEq(rest1, 0);
        assertEq(rest2, 0);

        // Zero inflow
        uint256[] memory normal = _generateTargets(10);
        (fills1, rest1) = waterFill1.pour(normal, 0);
        (fills2, rest2) = waterFill2.pour(normal, 0);
        for (uint256 i = 0; i < fills1.length; i++) {
            assertEq(fills1[i], 0);
            assertEq(fills2[i], 0);
        }
    }

    /// @notice Test different distribution patterns
    function testDistributionPatterns() public {
        // Uniform distribution
        uint256[] memory uniform = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            uniform[i] = 1000;
        }
        _testPattern(uniform, 50000);

        // Linear ascending
        uint256[] memory ascending = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            ascending[i] = (i + 1) * 100;
        }
        _testPattern(ascending, 250000);

        // Few large, many small
        uint256[] memory skewed = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            if (i < 10) {
                skewed[i] = 10000; // Large values
            } else {
                skewed[i] = 100; // Small values
            }
        }
        _testPattern(skewed, 50000);
    }

    function _testPattern(uint256[] memory targets, uint256 inflow) internal {
        (uint256[] memory fills1, uint256 rest1) = waterFill1.pour(targets, inflow);
        (uint256[] memory fills2, uint256 rest2) = waterFill2.pour(targets, inflow);

        // Verify correctness
        assertEq(rest1, rest2, "Rest should match for pattern");
        assertEq(fills1.length, fills2.length, "Array lengths should match for pattern");

        for (uint256 i = 0; i < fills1.length; i++) {
            assertEq(fills1[i], fills2[i], "Individual fills should match for pattern");
        }
    }

    /// @notice Test stress conditions
    function testStressConditions() public {
        // Large values (but not too large to avoid overflow)
        uint256[] memory largeValues = new uint256[](50);
        for (uint256 i = 0; i < 50; i++) {
            largeValues[i] = 1e15; // 1M ETH equivalent
        }
        _testPattern(largeValues, 25e15);

        // Many duplicates
        uint256[] memory duplicates = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            duplicates[i] = (i % 5) * 1000; // Only 5 unique values
        }
        _testPattern(duplicates, 100000);
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

    function _sumArray(uint256[] memory arr) internal pure returns (uint256 sum) {
        for (uint256 i = 0; i < arr.length; i++) {
            sum += arr[i];
        }
    }

    event GasComparison(uint256 indexed size, uint256 gas1, uint256 gas2, bool sorted_wins);
}
