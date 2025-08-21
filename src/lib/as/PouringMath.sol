// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// import {console} from "forge-std/console.sol";

library PouringMath {
    struct IndexedTarget {
        uint256 idx;
        uint256 target;
    }

    error LengthMismatch();

    /// @param shares The shares of each  entity
    /// @param amounts The current amounts allocated to each entity
    /// @param capacities The maximum capacities for each entity
    /// @param totalAmount The total inflow currently allocated across all entities
    /// @param inflow The new inflow to allocate
    function _allocate(
        uint256[] memory shares,
        uint256[] memory amounts,
        uint256[] memory capacities,
        uint256 totalAmount,
        uint256 inflow
    ) internal pure returns (uint256[] memory imbalance, uint256[] memory fills, uint256 rest) {
        uint256 n = shares.length;
        if (amounts.length != n || capacities.length != n) revert LengthMismatch();

        imbalance = new uint256[](n);
        fills = new uint256[](n);

        if (n == 0 || inflow == 0) {
            // nothing to do or nothing to distribute
            return (imbalance, fills, inflow);
        }

        totalAmount = totalAmount + inflow;
        _calcImbalanceInflow({
            imbalance: imbalance,
            shares: shares,
            amounts: amounts,
            capacities: capacities,
            fills: fills,
            totalAmount: totalAmount
        });
        // rest = _pourSimple(imbalance, fills, inflow);
        rest = _pourWaterFill(imbalance, fills, inflow);
    }

    /// @param shares The shares of each  entity
    /// @param amounts The current amounts allocated to each entity
    /// @param totalAmount The total inflow currently allocated across all entities
    /// @param outflow The new inflow to allocate
    function _deallocate(uint256[] memory shares, uint256[] memory amounts, uint256 totalAmount, uint256 outflow)
        internal
        pure
        returns (uint256[] memory imbalance, uint256[] memory fills, uint256 rest)
    {
        uint256 n = shares.length;
        if (amounts.length != n) revert LengthMismatch();

        imbalance = new uint256[](n);
        fills = new uint256[](n);

        unchecked {
            totalAmount = totalAmount < outflow ? 0 : totalAmount - outflow;
        }

        _calcImbalanceOutflow({
            imbalance: imbalance,
            shares: shares,
            amounts: amounts,
            fills: fills,
            totalAmount: totalAmount
        });
        // rest = _pourSimple(imbalance, fills, outflow);
        rest = _pourWaterFill(imbalance, fills, outflow);
    }

    // `capacity` - extra inflow for current entity that can be fitted into
    // i.e. max total inflow of current entity is `inflow + capacity`
    // capacity = 0, means no more can be added
    // `target` - max desired total inflow that should be allocated to current entity

    /// @param imbalance The current imbalance for each entity (mutated array)
    /// @param shares The shares of each  entity
    /// @param amounts The current amounts allocated to each entity
    /// @param capacities The maximum capacities for each entity
    /// @param fills The current fills for each entity (mutated array)
    /// @param totalAmount The total inflow currently allocated across all entities
    /// @dev imbalance is mutated arrays should be initialized before the call
    function _calcImbalanceInflow(
        uint256[] memory imbalance,
        uint256[] memory shares,
        uint256[] memory amounts,
        uint256[] memory capacities,
        uint256[] memory fills,
        uint256 totalAmount
    ) internal pure {
        uint256 n = shares.length;
        if (amounts.length != n || capacities.length != n || fills.length != n || imbalance.length != n) {
            revert LengthMismatch();
        }

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 target = shares[i];
                if (target != 0) {
                    target = Math.mulShr(target, totalAmount, 32, Math.Rounding.Ceil);
                    // console.log(
                    //     "target[%d] %d, share %d", i, target, Math.mulShr(shares[i], 100000, 32, Math.Rounding.Ceil)
                    // );
                }
                // console.log("inflow %d, fill %d", amounts[i], fills[i]);

                uint256 amt = amounts[i] + fills[i];
                target = target <= amt ? 0 : target - amt;
                if (target > 0) {
                    uint256 cap = capacities[i];
                    // console.log("cap %d", cap);
                    target = cap < target ? cap : target; // enforce capacity if limited
                }
                // console.log("target %d", target);
                imbalance[i] = target;
            }
        }
    }

    /// @param imbalance The current imbalance for each entity (mutated array)
    /// @param shares The shares of each  entity
    /// @param amounts The current amounts allocated to each entity
    /// @param fills The current fills for each entity (mutated array)
    /// @param totalAmount The total inflow currently allocated across all entities
    /// @dev imbalance is mutated arrays should be initialized before the call
    function _calcImbalanceOutflow(
        uint256[] memory imbalance,
        uint256[] memory shares,
        uint256[] memory amounts,
        uint256[] memory fills,
        uint256 totalAmount
    ) internal pure {
        uint256 n = shares.length;
        if (amounts.length != n || fills.length != n || imbalance.length != n) {
            revert LengthMismatch();
        }

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 target = shares[i];
                if (target != 0) {
                    // target = isShareUndefined[i] ? 0 : Math.mulShr(target, totalAmount, 32, Math.Rounding.Ceil);
                    target = Math.mulShr(target, totalAmount, 32, Math.Rounding.Ceil);
                    // console.log(
                    //     "target[%d] %d, share %d", i, target, Math.mulShr(shares[i], 100000, 32, Math.Rounding.Ceil)
                    // );
                }

                // console.log("inflow %d, fill %d", amounts[i], fills[i]);
                uint256 amt = amounts[i] - fills[i];
                target = amt <= target ? 0 : amt - target;
                // console.log("target %d", target);

                imbalance[i] = target;
            }
        }
    }

    /// @notice Simplified water-fill style allocator that distributes an `inflow` across baskets
    ///         toward absolute target amounts, respecting per-basket capacities.
    function _pourSimple(uint256[] memory targets, uint256[] memory fills, uint256 inflow)
        internal
        pure
        returns (uint256 rest)
    {
        uint256 n = targets.length;
        if (fills.length != n) revert LengthMismatch();

        // 0) Пустой массив
        if (n == 0) {
            return rest;
        }

        // Water-fill loop: distribute left across remaining deficits roughly evenly.
        // Complexity: O(k * n) where k is number of rounds; in worst case k <= max(deficit) when per==1.
        // bool[] memory active = new bool[](n);
        uint256 total;
        uint256 count;
        rest = inflow;

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 t = targets[i];
                if (t != 0) {
                    total += t;
                    ++count;
                }
            }
        }

        // console.log("total %d, rest %d, count %d", total, rest, count);
        if (total == 0 || rest == 0) {
            // console.log("early exit 1 - total %d, rest %d", total, rest);
            // nothing to do or nothing to distribute
            return rest;
        }

        if (rest >= total) {
            // Can satisfy all deficits outright
            unchecked {
                for (uint256 i; i < n; ++i) {
                    fills[i] = targets[i];
                    targets[i] = 0;
                }
                rest -= total;
            }
            // console.log("early exit 2 - total %d, rest %d", total, rest);
            return rest;
        }

        while (rest != 0 && count != 0) {
            uint256 per = rest / count;
            if (per == 0) per = 1;

            unchecked {
                for (uint256 i; i < n && rest != 0; ++i) {
                    // console.log("i %d, count %d, rest %d", i, count, rest);
                    uint256 need = targets[i];
                    // console.log("need %d", need);
                    if (need == 0) continue; // уже закрыт

                    uint256 use = need < per ? need : per;
                    if (use > rest) use = rest;
                    // console.log("use %d", use);
                    fills[i] += use;
                    targets[i] = need - use; // уменьшаем дефицит прямо в targets
                    rest -= use;
                    // console.log("targets[%d] %d, rest %d", i, targets[i], inflow);

                    if (targets[i] == 0) --count;
                }
            }
        }
    }

    function _pourWaterFill(uint256[] memory targets, uint256[] memory fills, uint256 inflow)
        internal
        pure
        returns (uint256 rest)
    {
        uint256 n = targets.length;
        if (fills.length != n) revert LengthMismatch();

        // 0) Empty array
        if (n == 0) {
            rest = inflow;
            return rest;
        }

        // 1) One element
        if (n == 1) {
            uint256 t = targets[0];
            uint256 pay = inflow >= t ? t : inflow;
            fills[0] = pay;
            rest = inflow > pay ? inflow - pay : 0;
            return (rest);
        }

        // 1) create array of IndexedTarget
        IndexedTarget[] memory items = new IndexedTarget[](n);
        for (uint256 i; i < n; ++i) {
            uint256 t = targets[i];
            items[i] = IndexedTarget({idx: i, target: t});
        }

        // 2) Quick sort by target DESC (pivot = middle element)
        _quickSort(items, int256(0), int256(n - 1));

        // 3) Compute prefix sums and quick path if inflow >= total
        uint256 total;
        uint256[] memory prefix = new uint256[](n);

        unchecked {
            for (uint256 i; i < n; ++i) {
                total += items[i].target;
                prefix[i] = total;
            }
        }
        if (total == 0) {
            rest = inflow;
            return rest;
        } else if (inflow >= total) {
            // всем платим full target
            unchecked {
                for (uint256 i; i < n; ++i) {
                    uint256 t = items[i].target;
                    if (t != 0) {
                        fills[items[i].idx] = t;
                        // targets[i] = 0;
                    }
                }
                rest = inflow - total;
            }
            return rest;
        }

        // 4) find level L: 1st k where
        //    items[k].target ≥ Lk ≥ nextTarget; Lk = (prefix[k]-inflow)/(k+1)
        uint256 level;
        unchecked {
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
        }

        // 5) final pass: fill = max(0, cap - L)
        uint256 used;
        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 t = items[i].target;
                uint256 pay = t > level ? t - level : 0;
                // console.log("items[%d].target %d", i, t);
                // console.log("pay %d", pay);
                // // console.log("imbalance[2] %d", imbalance[2]);
                if (pay > 0) {
                    uint256 idx = items[i].idx;
                    fills[idx] = pay;
                    targets[idx] = t - pay;
                    used += pay;
                }
            }
            rest = inflow > used ? inflow - used : 0;
        }
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
