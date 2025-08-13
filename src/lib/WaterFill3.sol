// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IWaterFill} from "../interfaces/IWaterFill.sol";

contract WaterFillSimple is IWaterFill {
    /**
     * @notice Разливает inflow по массиву target_i, чтобы
     * ∑_i max(0, target_i − lvl) = min(inflow, ∑target_i),
     * без сортировки.
     * @param targets — массив долгов
     * @param inflow    — сколько есть денег
     * @return fills  — сколько платим каждому
     * @return rest   — остаток (inflow − ∑fills)
     */
    function pour(uint256[] calldata targets, uint256 inflow)
        public
        pure
        returns (uint256[] memory fills, uint256 rest)
    {
        uint256 n = targets.length;
        fills = new uint256[](n);
        rest = inflow;

        // Water-fill loop: distribute left across remaining deficits roughly evenly.
        // Complexity: O(k * n) where k is number of rounds; in worst case k <= max(deficit) when per==1.
        // This matches style of original library (simple, gas-reasonable for small N).
        bool[] memory active = new bool[](n);
        uint256 totalDeficit;
        uint256 activeCount;

        unchecked {
            for (uint256 i; i < n; ++i) {
                uint256 t = targets[i];
                if (t != 0) {
                    active[i] = true;
                    totalDeficit += t;
                    ++activeCount;
                }
            }
        }

        if (totalDeficit == 0 || rest == 0) {
            // nothing to do or nothing to distribute
            return (fills, rest);
        }

        if (rest >= totalDeficit) {
            // Can satisfy all deficits outright
            for (uint256 i; i < n; ++i) {
                fills[i] = targets[i];
            }
            unchecked {
                rest -= totalDeficit;
            }
            return (fills, rest);
        }

        while (rest != 0 && activeCount != 0) {
            uint256 per = rest / activeCount;
            if (per == 0) per = 1;

            unchecked {
                for (uint256 i; i < n && rest != 0; ++i) {
                    if (!active[i]) continue;

                    uint256 need = targets[i] - fills[i];
                    if (need == 0) {
                        active[i] = false;
                        --activeCount;
                        continue;
                    }
                    uint256 use = need < per ? need : per;
                    if (use > rest) use = rest; // final partial slice
                    fills[i] += use;
                    rest -= use;

                    if (use == need) {
                        active[i] = false;
                        --activeCount;
                    }
                }
            }
        }
    }
}
