// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {IWaterFill} from "../interfaces/IWaterFill.sol";
contract WaterFillNoSort is IWaterFill {
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

        // 1) найдём maxTarget
        uint256 maxT;
        for (uint256 i = 0; i < n; ++i) {
            if (targets[i] > maxT) maxT = targets[i];
        }

        // 2) бинарим lvl в [0..maxT]
        uint256 lo = 0;
        uint256 hi = maxT;
        while (lo < hi) {
            // mid bias вверх: хотим найти наибольшее lvl с sum>=inflow
            uint256 mid = (lo + hi + 1) >> 1;
            // считаем, сколько воды уйдёт при уровне mid
            uint256 s;
            for (uint256 i = 0; i < n; ++i) {
                if (targets[i] > mid) {
                    s += (targets[i] - mid);
                    if (s >= inflow) break; // ранний выход
                }
            }
            // если можем «залить» ≥ inflow → уровень слишком низкий (должен поднять)
            if (s >= inflow) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        uint256 lvl = lo;

        // 3) финальные выплаты и остаток
        uint256 used;
        for (uint256 i = 0; i < n; ++i) {
            uint256 t = targets[i];
            if (t > lvl) {
                uint256 pay = t - lvl;
                fills[i] = pay;
                used += pay;
            }
        }
        rest = inflow > used ? inflow - used : 0;
    }
}
