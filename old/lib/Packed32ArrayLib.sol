// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

library Packed32ArrayLib {
    error OutOfBounds();
    error EmptyArray();

    struct PackedArray {
        uint256 length; // количество элементов
        bytes data; // каждый элемент ровно 32 байта (packed)
    }

    // ----- Базовые методы -----

    function get(PackedArray storage arr, uint256 index) internal view returns (bytes32 val) {
        if (index >= arr.length) revert OutOfBounds();
        uint256 offset = index * 32;
        bytes storage data = arr.data;
        uint256 baseSlot;
        assembly {
            baseSlot := keccak256(add(data.slot, 0x0), 0x20)
            val := sload(add(baseSlot, div(offset, 32)))
        }
    }

    function set(PackedArray storage arr, uint256 index, bytes32 val) internal {
        if (index >= arr.length) revert OutOfBounds();
        uint256 offset = index * 32;
        bytes storage data = arr.data;
        uint256 baseSlot;
        assembly {
            baseSlot := keccak256(add(data.slot, 0x0), 0x20)
            sstore(add(baseSlot, div(offset, 32)), val)
        }
    }

    function push(PackedArray storage arr, bytes32 val) internal {
        bytes storage data = arr.data;
        uint256 length = arr.length;
        uint256 offset = length * 32;
        uint256 baseSlot;
        assembly {
            baseSlot := keccak256(add(data.slot, 0x0), 0x20)
        }
        assembly {
            sstore(add(baseSlot, div(offset, 32)), val) //??
        }
        ++length;
        // обновим длину bytes для корректности
        arr.length = length;
        assembly {
            sstore(data.slot, mul(length, 32))
        }
    }

    function pop(PackedArray storage arr) internal returns (bytes32 val) {
        if (arr.length == 0) revert EmptyArray();
        uint256 index = arr.length - 1;
        val = get(arr, index);
        arr.length = index;
        bytes storage data = arr.data;
        // обновим длину bytes для корректности
        assembly {
            sstore(data.slot, mul(index, 32))
        }
    }
}
