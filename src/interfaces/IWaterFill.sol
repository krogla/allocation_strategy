// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IWaterFill {
    function pour(uint256[] calldata targets, uint256 inflow)
        external
        pure
        returns (uint256[] memory fills, uint256 rest);
}
