// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library GeneralPackedArrayLib {
    struct PackedArray {
        uint256 length; // кол-во элементов
        bytes data; // данные: packed элементы подряд
    }

    // ---- "Core" методы работы с массивом ----

    // Получить элемент как bytes
    // Чтение элемента по индексу (возвращает bytes)
    function getRaw(PackedArray storage arr, uint256 index, uint256 elementSize)
        internal
        view
        returns (bytes memory element)
    {
        require(index < arr.length, "OOB");
        uint256 offset = index * elementSize;
        element = new bytes(elementSize);

        bytes storage data = arr.data;
        uint256 slot;
        assembly {
            mstore(0x0, data.slot)
            slot := keccak256(0x0, 0x20)
        }

        // Если элемент > 32 байт
        if (elementSize > 32) {
            uint256 fullSlots = elementSize / 32;
            uint256 tail = elementSize % 32;

            for (uint256 i = 0; i < fullSlots; ++i) {
                uint256 val;
                assembly {
                    val := sload(add(slot, div(add(offset, mul(i, 32)), 32)))
                }
                assembly {
                    mstore(add(element, add(32, mul(i, 32))), val)
                }
            }
            if (tail > 0) {
                uint256 val;
                assembly {
                    val := sload(add(slot, div(add(offset, mul(fullSlots, 32)), 32)))
                }
                // Сдвинуть влево на (32 - tail) байт, затем в элемент
                uint256 destPtr = 32 + fullSlots * 32;
                assembly {
                    mstore(add(element, add(32, mul(fullSlots, 32))), shr(mul(8, sub(32, tail)), val))
                }
            }
        } else {
            // ≤ 32 байт, читаем одним sload
            uint256 val;
            uint256 slotOffset = offset / 32;
            uint256 offsetInSlot = offset % 32;
            assembly {
                val := sload(add(slot, slotOffset))
            }
            // Сдвигаем, маскируем
            val = val << (offsetInSlot * 8);
            val = val >> ((32 - elementSize) * 8); // только нужные байты влево, потом вправо
            assembly {
                mstore(add(element, 32), val)
            }
        }
    }

    // Запись элемента (bytes element -> storage)
    function setRaw(PackedArray storage arr, uint256 index, bytes memory element, uint256 elementSize) internal {
        require(index < arr.length, "OOB");
        require(element.length == elementSize, "Bad size");
        uint256 offset = index * elementSize;

        bytes storage data = arr.data;
        uint256 slot;
        assembly {
            mstore(0x0, data.slot)
            slot := keccak256(0x0, 0x20)
        }

        if (elementSize > 32) {
            uint256 fullSlots = elementSize / 32;
            uint256 tail = elementSize % 32;
            for (uint256 i = 0; i < fullSlots; ++i) {
                uint256 val;
                assembly {
                    val := mload(add(element, add(32, mul(i, 32))))
                }
                assembly {
                    sstore(add(slot, div(add(offset, mul(i, 32)), 32)), val)
                }
            }
            if (tail > 0) {
                uint256 lastSlot = add(slot, div(add(offset, mul(fullSlots, 32)), 32));
                uint256 oldVal;
                assembly {
                    oldVal := sload(lastSlot)
                }
                uint256 mask = (1 << (8 * (32 - tail))) - 1;
                uint256 newVal;
                assembly {
                    newVal := mload(add(element, add(32, mul(fullSlots, 32))))
                }
                newVal = newVal >> (8 * (32 - tail)); // только нужные байты
                uint256 result = (oldVal & mask) | (newVal << (8 * (32 - tail)));
                assembly {
                    sstore(lastSlot, result)
                }
            }
        } else {
            uint256 slotOffset = offset / 32;
            uint256 offsetInSlot = offset % 32;
            uint256 val;
            assembly {
                val := mload(add(element, 32))
            }
            uint256 storageVal;
            uint256 slotAddr = slot + slotOffset;
            assembly {
                storageVal := sload(slotAddr)
            }
            // Подготовим маску: зануляем нужные байты, вставляем val
            uint256 mask = ~(((1 << (8 * elementSize)) - 1) << (8 * (32 - offsetInSlot - elementSize)));
            storageVal = (storageVal & mask) | (val << (8 * (32 - offsetInSlot - elementSize)));
            assembly {
                sstore(slotAddr, storageVal)
            }
        }
    }

    // Push (добавление) — максимально эффективный вариант
    function pushRaw(PackedArray storage arr, bytes memory element, uint256 elementSize) internal {
        require(element.length == elementSize, "Wrong element size");
        bytes storage data = arr.data;

        // "Дозаписываем" новые байты прямо в storage
        assembly {
            let dataLen := sload(data.slot)
            let newLen := add(dataLen, elementSize)
            sstore(data.slot, newLen) // обновляем длину bytes в storage

            // куда писать
            let destPtr := add(add(mload(add(arr, 0x20)), 0x20), dataLen)
            let srcPtr := add(element, 0x20)

            for { let i := 0 } lt(i, elementSize) { i := add(i, 0x20) } {
                mstore(add(destPtr, i), mload(add(srcPtr, i)))
            }
        }
        arr.length += 1;
    }

    // Pop (удаление последнего элемента)
    function popRaw(PackedArray storage arr, uint256 elementSize) internal returns (bytes memory element) {
        require(arr.length > 0, "Empty array");
        uint256 idx = arr.length - 1;
        element = getRaw(arr, idx, elementSize);

        // сокращаем длину bytes
        bytes storage data = arr.data;
        assembly {
            let dataLen := sload(data.slot)
            sstore(data.slot, sub(dataLen, elementSize))
        }
        arr.length -= 1;
    }

    // Читаем N подряд элементов, каждый elementSize байт.
    // Возвращаем массив bytes[] — каждый элемент отдельный bytes (или можно MemoryView, если надо)
    function batchGetRaw(PackedArray storage arr, uint256 fromIndex, uint256 count, uint256 elementSize)
        internal
        view
        returns (bytes[] memory elements)
    {
        require(fromIndex + count <= arr.length, "OOB");

        // Вычисляем, сколько байт нужно прочитать с "запасом":
        uint256 startOffset = fromIndex * elementSize;
        uint256 totalBytes = count * elementSize;

        // Вычисляем storage-слот начала и конца
        bytes storage data = arr.data;
        uint256 slot;
        assembly {
            mstore(0x0, data.slot)
            slot := keccak256(0x0, 0x20)
        }
        uint256 startSlot = startOffset / 32;
        uint256 endSlot = (startOffset + totalBytes + 31) / 32; // округление вверх
        uint256 slotCount = endSlot - startSlot;

        // Считываем всё "поле" одним большим Memory blob (размером slotCount*32 байт)
        bytes memory blob = new bytes(slotCount * 32);
        for (uint256 i = 0; i < slotCount; ++i) {
            uint256 val;
            assembly {
                val := sload(add(slot, add(startSlot, i)))
            }
            assembly {
                mstore(add(blob, add(32, mul(i, 32))), val)
            }
        }

        // Теперь blob содержит всё, что нужно. Разбираем на элементы:
        elements = new bytes[](count);
        uint256 offsetInBlob = startOffset % 32;
        for (uint256 k = 0; k < count; ++k) {
            bytes memory el = new bytes(elementSize);
            // копируем элементSize байт
            for (uint256 b = 0; b < elementSize; ++b) {
                el[b] = blob[offsetInBlob + b];
            }
            elements[k] = el;
            offsetInBlob += elementSize;
        }
    }

      // Считать N подряд элементов фиксированного размера из packed storage bytes
    function batchGetRaw(
        PackedArray storage arr,
        uint256 fromIndex,
        uint256 count,
        uint256 elementSize
    ) internal view returns (bytes[] memory elements) {
        require(fromIndex + count <= arr.length, "OOB");
        require(elementSize > 0, "elementSize=0");

        // Начальная позиция в байтах
        uint256 startOffset = fromIndex * elementSize;
        uint256 totalBytes = count * elementSize;

        // Используем современный способ вычисления первого слота storage массива bytes
        bytes storage data = arr.data;
        uint256 baseSlot;
        assembly { baseSlot := keccak256(add(data.slot, 0x0), 0x20) }

        // В каких storage-слотах лежит диапазон? (startSlot, endSlot)
        uint256 startSlot = startOffset / 32;
        uint256 endSlot = (startOffset + totalBytes + 31) / 32; // ceil
        uint256 slotCount = endSlot - startSlot;

        // Читаем нужные storage-слоты в blob (с запасом)
        bytes memory blob = new bytes(slotCount * 32);
        for (uint256 i = 0; i < slotCount; ++i) {
            uint256 val;
            assembly {
                val := sload(add(baseSlot, add(startSlot, i)))
                mstore(add(blob, add(32, mul(i, 32))), val)
            }
        }

        // Разбираем blob на элементы
        elements = new bytes[](count);
        uint256 offsetInBlob = startOffset % 32;
        for (uint256 k = 0; k < count; ++k) {
            bytes memory el = new bytes(elementSize);
            // копируем elementSize байт (простая memory-копия)
            for (uint256 b = 0; b < elementSize; ++b) {
                el[b] = blob[offsetInBlob + b];
            }
            elements[k] = el;
            offsetInBlob += elementSize;
        }
    }

    // Пример getRaw (чтение одного элемента)
    function getRaw(
        PackedArray storage arr,
        uint256 index,
        uint256 elementSize
    ) internal view returns (bytes memory element) {
        bytes[] memory batch = batchGetRaw(arr, index, 1, elementSize);
        return batch[0];
    }
}
