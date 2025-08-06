// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IWaterFill} from "../interfaces/IWaterFill.sol";

contract WaterFillOptimized is IWaterFill {
    struct IndexedTarget {
        uint256 idx;
        uint256 target;
    }

    /**
     * @dev Быстрое распределение `inflow` по `targets`
     *    на n≈300–500 элементов. O(n log n) сортировка + несколько O(n) проходов.
     */
    function pour(uint256[] calldata targets, uint256 inflow)
        public
        pure
        returns (uint256[] memory fills, uint256 rest)
    {
        uint256 n = targets.length;
        fills = new uint256[](n);

        // 0) Пустой массив
        if (n == 0) {
            rest = inflow;
            return (fills, rest);
        }
        // 1) Один элемент
        if (n == 1) {
            uint256 t = targets[0];
            uint256 pay = inflow >= t ? t : inflow;
            fills[0] = pay;
            rest = inflow > pay ? inflow - pay : 0;
            return (fills, rest);
        }

        // 1) Собираем IndexedTarget {-структуры в памяти
        IndexedTarget[] memory items = new IndexedTarget[](n);
        for (uint256 i; i < n; ++i) {
            uint256 t = targets[i];
            items[i] = IndexedTarget({idx: i, target: t});
        }

        // 2) Быстрая сортировка по target DESC (pivot = middle element)
        _quickSort(items, int256(0), int256(n - 1));

        // 3) Префикс-суммы cap, и быстрый путь если inflow >= total
        uint256 total;
        uint256[] memory prefix = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            total += items[i].target;
            prefix[i] = total;
        }
        if (total == 0) {
            rest = inflow;
            return (fills, rest);
        } else if (inflow >= total) {
            // всем платим full target
            for (uint256 i; i < n; ++i) {
                fills[items[i].idx] = items[i].target;
            }
            rest = inflow - total;
            return (fills, rest);
        }

        // 4) Ищем уровень L: первый k где
        //    items[k].target ≥ Lk ≥ nextTarget; Lk = (prefix[k]-inflow)/(k+1)
        uint256 level;
        for (uint256 k; k < n; ++k) {
            if (prefix[k] < inflow) {
                continue;
            }
            level = (prefix[k] - inflow) / (k + 1);
            uint256 nextTarget = k + 1 < n ? items[k + 1].target : 0;
            if (items[k].target >= level && level >= nextTarget) {
                break;
            }
        }

        // 5) Финальный pass: fill = max(0, cap - L)
        uint256 used;
        for (uint256 i; i < n; ++i) {
            uint256 t = items[i].target;
            uint256 pay = t > level ? t - level : 0;
            fills[items[i].idx] = pay;
            used += pay;
        }
        rest = inflow > used ? inflow - used : 0;
    }

    /// @dev In-place quicksort on IndexedTarget {[] by target DESC, tiebreaker idx ASC.
    function _quickSort(IndexedTarget[] memory arr, int256 left, int256 right) internal pure {
        if (left >= right) return;
        int256 i = left;
        int256 j = right;
        // Pivot = middle element's target
        uint256 pivot = arr[uint256((left + right) / 2)].target;
        while (i <= j) {
            // move i forward while arr[i].target > pivot
            while (arr[uint256(i)].target > pivot) {
                unchecked {
                    ++i;
                }
            }
            // move j backward while arr[j].target < pivot
            while (arr[uint256(j)].target < pivot) {
                unchecked {
                    --j;
                }
            }
            if (i <= j) {
                // swap arr[i] <-> arr[j]
                // IndexedTarget {memory tmp = arr[uint256(i)];
                // arr[uint256(i)] = arr[uint256(j)];
                // arr[uint256(j)] = tmp;
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
                unchecked {
                    ++i;
                    --j;
                }
            }
        }
        if (left < j) _quickSort(arr, left, j);
        if (i < right) _quickSort(arr, i, right);
    }
}
