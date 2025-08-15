// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {CommonBase, Vm} from "forge-std/Base.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @author madlabman
contract Utilities is CommonBase {
    bytes32 internal seed = keccak256("seed sEed seEd");

    function nextAddress() internal returns (address) {
        bytes32 buf = keccak256(abi.encodePacked(seed));
        address a = address(uint160(uint256(buf)));
        seed = buf;
        return a;
    }

    function nextAddress(string memory label) internal returns (address) {
        address a = nextAddress();
        vm.label(a, label);
        return a;
    }

    function expectRoleRevert(address account, bytes32 neededRole) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, neededRole)
        );
    }

    function convertArrUint8toUint256(uint8[] memory array8) internal pure returns (uint256[] memory array256) {
        array256 = new uint256[](array8.length);
        for (uint256 i = 0; i < array8.length; i++) {
            array256[i] = array8[i];
        }
    }

    function convertArrUint16toUint256(uint16[] memory array16) internal pure returns (uint256[] memory array256) {
        array256 = new uint256[](array16.length);
        for (uint256 i = 0; i < array16.length; i++) {
            array256[i] = array16[i];
        }
    }

    function convertArrUint32toUint256(uint32[] memory array32) internal pure returns (uint256[] memory array256) {
        array256 = new uint256[](array32.length);
        for (uint256 i = 0; i < array32.length; i++) {
            array256[i] = array32[i];
        }
    }

    function convertArrFixed16ToUint256(uint256[16] memory array) internal pure returns (uint256[] memory array256) {
        array256 = new uint256[](array.length);
        for (uint256 i = 0; i < array.length; i++) {
            array256[i] = array[i];
        }
    }

    function generateVals(uint256 size, uint16 min, uint16 max, uint256 rounding)
        internal
        returns (uint16[] memory targets)
    {
        targets = new uint16[](size);
        for (uint256 i = 0; i < targets.length; i++) {
            // Generate pseudo-random values between min and max
            seed = keccak256(abi.encode(seed, i));
            uint256 res = (uint256(seed) % (max - min + 1)) + min;
            // round to nearest
            targets[i] = uint16(rounding > 1 ? res / rounding * rounding : res);
        }
    }
}
