// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {WaterFillOptimized} from "../src/lib/WaterFill1.sol";
import {WaterFillNoSort} from "../src/lib/WaterFill2.sol";
import {IWaterFill} from "../src/interfaces/IWaterFill.sol";

/// @title WaterFill Algorithm Comparison Test
/// @notice Comprehensive analysis of different water filling algorithms
/// @dev Tests correctness, gas costs, and performance across various input sizes
contract WaterFillComparisonTest is Test {
    IWaterFill public waterFill1;
    IWaterFill public waterFill2;

    // Test sizes for performance analysis
    // uint256[] testSizes = [20, 100, 400];//, 800]; //, 1000, 2000];
    // uint256[] testSizes = [500, 600, 700];//, 800]; //, 1000, 2000];
    uint256[] testSizes = [999]; //, 800]; //, 1000, 2000];

    struct TestResult {
        uint256 gasUsed;
        uint256[] fills;
        uint256 rest;
        bool success;
        string errorMessage;
    }

    struct ComparisonData {
        uint256 inputSize;
        uint256 inflow;
        TestResult sortedResult; // WaterFill1 (with sorting)
        TestResult binaryResult; // WaterFill2 (binary search)
        uint256 gasDifference;
        bool resultsMatch;
    }

    function setUp() public {
        waterFill1 = new WaterFillOptimized();
        waterFill2 = new WaterFillNoSort();
    }

    /// @notice Main comparison test across all input sizes
    function testWaterFillComparison() public {
        console.log("=== WATER FILL ALGORITHM COMPARISON ===\n");

        ComparisonData[] memory results = new ComparisonData[](testSizes.length * 3); // 3 scenarios per size
        uint256 resultIndex = 0;

        for (uint256 i = 0; i < testSizes.length; i++) {
            uint256 size = testSizes[i];
            console.log("Testing size:", size);

            // Scenario 1: Low inflow (25% of total targets)
            results[resultIndex++] = _runComparison(size, "low_inflow", 25);

            // Scenario 2: Medium inflow (75% of total targets)
            results[resultIndex++] = _runComparison(size, "medium_inflow", 75);

            // Scenario 3: High inflow (150% of total targets)
            results[resultIndex++] = _runComparison(size, "high_inflow", 150);

            console.log("");
        }

        _printSummaryAnalysis(results, resultIndex);
    }

    /// @notice Test correctness with edge cases
    function testEdgeCases() public {
        console.log("=== EDGE CASES TESTING ===\n");

        // Empty array
        _testEdgeCase("Empty array", new uint256[](0), 1000);

        // Single element
        uint256[] memory single = new uint256[](1);
        single[0] = 500;
        _testEdgeCase("Single element", single, 300);

        // All zeros
        uint256[] memory zeros = new uint256[](5);
        _testEdgeCase("All zeros", zeros, 1000);

        // All same values
        uint256[] memory same = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            same[i] = 100;
        }
        _testEdgeCase("All same values", same, 300);

        // Zero inflow
        uint256[] memory normal = _generateTargets(10, 12345);
        _testEdgeCase("Zero inflow", normal, 0);

        // Huge inflow
        _testEdgeCase("Huge inflow", normal, type(uint256).max / 1000);
    }

    /// @notice Test with different distribution patterns
    function testDistributionPatterns() public {
        console.log("=== DISTRIBUTION PATTERNS TESTING ===\n");

        uint256 size = 100;

        // Uniform distribution
        uint256[] memory uniform = _generateUniformTargets(size, 1000);
        _testPattern("Uniform", uniform, _sumArray(uniform) / 2);

        // Linear ascending
        uint256[] memory ascending = _generateLinearTargets(size, 10, 1000);
        _testPattern("Linear ascending", ascending, _sumArray(ascending) / 2);

        // Exponential distribution
        uint256[] memory exponential = _generateExponentialTargets(size, 2);
        _testPattern("Exponential", exponential, _sumArray(exponential) / 2);

        // Few large, many small
        uint256[] memory skewed = _generateSkewedTargets(size);
        _testPattern("Skewed (few large)", skewed, _sumArray(skewed) / 2);
    }

    /// @notice Stress test with large arrays
    function testStressConditions() public {
        console.log("=== STRESS TESTING ===\n");

        // Very large values
        uint256[] memory largeValues = new uint256[](50);
        for (uint256 i = 0; i < 50; i++) {
            largeValues[i] = type(uint256).max / 100; // Avoid overflow
        }
        _testStress("Large values", largeValues, _sumArray(largeValues) / 3);

        // Many duplicates
        uint256[] memory duplicates = new uint256[](100);
        for (uint256 i = 0; i < 100; i++) {
            duplicates[i] = (i % 5) * 1000; // Only 5 unique values
        }
        _testStress("Many duplicates", duplicates, _sumArray(duplicates) / 2);
    }

    /// @notice Run comparison for specific size and scenario
    function _runComparison(uint256 size, string memory scenario, uint256 inflowPercent)
        internal
        returns (ComparisonData memory result)
    {
        // Generate test data
        uint256[] memory targets = _generateTargets(size, block.timestamp + size);
        uint256 totalTargets = _sumArray(targets);
        uint256 inflow = (totalTargets * inflowPercent) / 100;

        result.inputSize = size;
        result.inflow = inflow;

        // Test WaterFill1 (sorted approach)
        result.sortedResult = _measureGas(waterFill1, targets, inflow);

        // Test WaterFill2 (binary search approach)
        result.binaryResult = _measureGas(waterFill2, targets, inflow);

        // Calculate differences
        if (result.sortedResult.success && result.binaryResult.success) {
            result.gasDifference = result.sortedResult.gasUsed > result.binaryResult.gasUsed
                ? result.sortedResult.gasUsed - result.binaryResult.gasUsed
                : result.binaryResult.gasUsed - result.sortedResult.gasUsed;
            result.resultsMatch = _compareResults(result.sortedResult.fills, result.binaryResult.fills);
        }

        console.log("  ", scenario, ":");
        console.log("    Sorted=", result.sortedResult.gasUsed, " gas");
        console.log("    Binary=", result.binaryResult.gasUsed, " gas");
        console.log("    Match=", result.resultsMatch ? "PASS" : "FAIL");
    }

    /// @notice Measure gas usage for a water fill algorithm
    function _measureGas(IWaterFill impl, uint256[] memory targets, uint256 inflow)
        internal
        returns (TestResult memory result)
    {
        uint256 gasBefore = gasleft();
        try this._callWaterFill(impl, targets, inflow) returns (uint256[] memory fills, uint256 rest) {
            uint256 gasAfter = gasleft();
            result.gasUsed = gasBefore - gasAfter;
            result.fills = fills;
            result.rest = rest;
            result.success = true;
        } catch Error(string memory reason) {
            result.errorMessage = reason;
            result.success = false;
        } catch {
            result.errorMessage = "Unknown error";
            result.success = false;
        }
        if (!result.success) {
            console.log("Error:", result.errorMessage);
        }
    }

    /// @notice External call wrappers for gas measurement
    function _callWaterFill(IWaterFill impl, uint256[] calldata targets, uint256 inflow)
        external
        returns (uint256[] memory, uint256)
    {
        return impl.pour(targets, inflow);
    }

    /// @notice Generate pseudo-random targets
    function _generateTargets(uint256 size, uint256 seed) internal pure returns (uint256[] memory) {
        uint256[] memory targets = new uint256[](size);
        uint256 rng = seed;

        for (uint256 i = 0; i < size; i++) {
            rng = uint256(keccak256(abi.encode(rng, i))) % 100000; // 0-99999 range
            targets[i] = rng + 1; // Avoid zero
        }

        return targets;
    }

    /// @notice Generate uniform distribution
    function _generateUniformTargets(uint256 size, uint256 value) internal pure returns (uint256[] memory) {
        uint256[] memory targets = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            targets[i] = value;
        }
        return targets;
    }

    /// @notice Generate linear distribution
    function _generateLinearTargets(uint256 size, uint256 start, uint256 step)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory targets = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            targets[i] = start + i * step;
        }
        return targets;
    }

    /// @notice Generate exponential distribution
    function _generateExponentialTargets(uint256 size, uint256 base) internal pure returns (uint256[] memory) {
        uint256[] memory targets = new uint256[](size);
        uint256 value = 1;
        for (uint256 i = 0; i < size; i++) {
            targets[i] = value;
            value = value * base;
            if (value > 1000000) value = 1; // Reset to avoid overflow
        }
        return targets;
    }

    /// @notice Generate skewed distribution (few large, many small)
    function _generateSkewedTargets(uint256 size) internal pure returns (uint256[] memory) {
        uint256[] memory targets = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            if (i < size / 10) {
                targets[i] = 50000 + i * 10000; // 10% large values
            } else {
                targets[i] = 100 + (i % 10) * 50; // 90% small values
            }
        }
        return targets;
    }

    /// @notice Sum array elements
    function _sumArray(uint256[] memory arr) internal pure returns (uint256 sum) {
        for (uint256 i = 0; i < arr.length; i++) {
            sum += arr[i];
        }
    }

    /// @notice Compare two fill results
    function _compareResults(uint256[] memory fills1, uint256[] memory fills2) internal pure returns (bool) {
        if (fills1.length != fills2.length) {
            console.log("!! length mismatch %d=$d", fills1.length, fills2.length);
            return false;
        }
        bool ok = true;
        for (uint256 i = 0; i < fills1.length; i++) {
            if (fills1[i] != fills2[i]) {
                console.log("!! mismatch at index %d: %d != %d", i, fills1[i], fills2[i]);
                ok = false;
            }
        }

        return ok;
    }

    /// @notice Test edge case
    function _testEdgeCase(string memory name, uint256[] memory targets, uint256 inflow) internal {
        console.log("Testing:", name);

        TestResult memory result1 = _measureGas(waterFill1, targets, inflow);
        TestResult memory result2 = _measureGas(waterFill2, targets, inflow);

        bool isMatch = result1.success && result2.success && _compareResults(result1.fills, result2.fills)
            && result1.rest == result2.rest;

        console.log(
            "  Result: %s, Gas: Sorted=%d, Binary=%d", isMatch ? "PASS" : "FAIL", result1.gasUsed, result2.gasUsed
        );

        if (!isMatch && result1.success && result2.success) {
            console.log("  ERROR: Results don't match!");
            console.log("  Sorted rest:", result1.rest, "Binary rest:", result2.rest);
        }
    }

    /// @notice Test distribution pattern
    function _testPattern(string memory name, uint256[] memory targets, uint256 inflow) internal {
        console.log("Testing pattern:", name);

        TestResult memory result1 = _measureGas(waterFill1, targets, inflow);
        TestResult memory result2 = _measureGas(waterFill2, targets, inflow);

        bool isMatching = result1.success && result2.success && _compareResults(result1.fills, result2.fills);

        console.log(
            "  Gas efficiency: Sorted=%d, Binary=%d, Winner=%s",
            result1.gasUsed,
            result2.gasUsed,
            result1.gasUsed < result2.gasUsed ? "Sorted" : "Binary"
        );

        console.log("  Correctness: %s", isMatching ? "PASS" : "FAIL");
    }

    /// @notice Test stress conditions
    function _testStress(string memory name, uint256[] memory targets, uint256 inflow) internal {
        console.log("Stress test:", name);

        TestResult memory result1 = _measureGas(waterFill1, targets, inflow);
        TestResult memory result2 = _measureGas(waterFill2, targets, inflow);

        console.log("  Sorted: %s (gas: %d)", result1.success ? "PASS" : "FAIL", result1.gasUsed);
        console.log("  Binary: %s (gas: %d)", result2.success ? "PASS" : "FAIL", result2.gasUsed);

        if (result1.success && result2.success) {
            bool isMatching = _compareResults(result1.fills, result2.fills);
            console.log("  Results match: %s", isMatching ? "PASS" : "FAIL");
        }
    }

    /// @notice Print comprehensive analysis
    function _printSummaryAnalysis(ComparisonData[] memory results, uint256 count) internal view {
        console.log("=== COMPREHENSIVE ANALYSIS ===\n");

        uint256 sortedWins = 0;
        uint256 binaryWins = 0;
        uint256 totalGasSorted = 0;
        uint256 totalGasBinary = 0;
        uint256 correctnessFailures = 0;

        console.log("Size\tScenario\tSorted Gas\tBinary Gas\tWinner\tMatch");
        console.log("----\t--------\t----------\t----------\t------\t-----");

        for (uint256 i = 0; i < count; i++) {
            ComparisonData memory data = results[i];

            if (data.sortedResult.success && data.binaryResult.success) {
                totalGasSorted += data.sortedResult.gasUsed;
                totalGasBinary += data.binaryResult.gasUsed;

                string memory winner = data.sortedResult.gasUsed < data.binaryResult.gasUsed ? "Sorted" : "Binary";
                if (data.sortedResult.gasUsed < data.binaryResult.gasUsed) {
                    sortedWins++;
                } else {
                    binaryWins++;
                }

                if (!data.resultsMatch) {
                    correctnessFailures++;
                }

                string memory scenario = i % 3 == 0 ? "Low" : (i % 3 == 1 ? "Med" : "High");
                console.log("%d\t%s", data.inputSize, scenario);
                console.log("\t\t%d\t\t%d", data.sortedResult.gasUsed, data.binaryResult.gasUsed);
                console.log("\t%s\t%s", winner, data.resultsMatch ? "PASS" : "FAIL");

                // console.log(
                //     "%d\t%s\t\t%d\t\t%d\t\t%s\t%s",
                //     data.inputSize,
                //     scenario,
                //     data.sortedResult.gasUsed,
                //     data.binaryResult.gasUsed,
                //     winner,
                //     data.resultsMatch ? "PASS" : "FAIL"
                // );
            }
        }

        console.log("\n=== FINAL SUMMARY ===");
        console.log("Sorted algorithm wins: %d", sortedWins);
        console.log("Binary algorithm wins: %d", binaryWins);
        console.log("Average gas - Sorted: %d", totalGasSorted / count);
        console.log("Average gas - Binary: %d", totalGasBinary / count);
        console.log("Correctness failures: %d", correctnessFailures);

        // Performance analysis
        console.log("\n=== PERFORMANCE INSIGHTS ===");
        if (sortedWins > binaryWins) {
            console.log("- Sorted approach is more gas efficient overall");
            console.log("- O(n log n) complexity pays off for typical inputs");
        } else {
            console.log("- Binary search approach is more gas efficient overall");
            console.log("- O(n log max_target) complexity wins for this data");
        }

        if (correctnessFailures > 0) {
            console.log("- WARNING: %d correctness failures detected!", correctnessFailures);
        } else {
            console.log("- All algorithms produce identical results (PASS)");
        }
    }
}
