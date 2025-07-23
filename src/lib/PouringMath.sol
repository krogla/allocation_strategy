// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @dev 1e4 = 100 %
uint256 constant BIPS = 1e4;

struct Basket {
    uint256 amount; // уже лежит
    uint256 capacity; // 0 == безлимит
    uint256 targetShareBps; // желаемая доля, 0 если нет target
    uint256 protectShareBps; // верхняя планка «не трогать при отсыпании»
}

struct BasketCache {
    // копия входных данных
    uint256 amount;
    uint256 capacity;
    uint256 targetBps; // 0, 1…9999, 10000
    uint256 protectBps; // 0 => use targetBps
    // pre-computed / runtime state
    bool active; // участвует в текущем water-fill
    uint256 ideal; // min(capacity, targetBps * total / BIPS) - // where we WANT to be
    uint256 protect; // min(capacity, protectBps * total / BIPS) - // don’t withdraw below
}

library PouringMath {
    /*──────────────────────── PUBLIC ────────────────────────*/

    function computeDeposits(BasketCache[] memory bc, uint256 inflow)
        internal
        pure
        returns (uint256[] memory alloc, uint256 left)
    {
        uint256 n = bc.length;
        alloc = new uint256[](n);
        uint256 total = _sumAmounts(bc) + inflow;

        _precompute(bc, total);

        left = inflow;

        /* Phase A: добиваем корзины с 0 < target < 100 % */
        for (uint256 i; i < n; ++i) {
            bc[i].active = (bc[i].targetBps > 0 && bc[i].targetBps < BIPS && bc[i].amount < bc[i].ideal);
        }
        left -= _waterFillDeposit(bc, alloc, left);

        /* Phase B: “резиновые” target = 100 % */
        if (left > 0) {
            for (uint256 i; i < n; ++i) {
                bc[i].active = (bc[i].targetBps == BIPS && bc[i].amount < bc[i].capacity);
            }
            left -= _waterFillDeposit(bc, alloc, left);
        }

        // require(left == 0, "Excess inflow: capacities saturated");
    }

    function computeWithdrawals(BasketCache[] memory bc, uint256 outflow)
        internal
        pure
        returns (uint256[] memory take, uint256 left)
    {
        uint256 n = bc.length;
        take = new uint256[](n);
        uint256 total = _sumAmounts(bc) - outflow;

        _precompute(bc, total);

        left = outflow;

        /* Phase 0: опустошаем “чёрные” target = 0 % */
        for (uint256 i; i < n; ++i) {
            bc[i].active = (bc[i].targetBps == 0 && bc[i].amount > 0);
        }
        left -= _waterFillWithdraw(bc, take, left);

        /* Phase 1: всё, что выше protect */
        if (left > 0) {
            for (uint256 i; i < n; ++i) {
                bc[i].active = (bc[i].amount > bc[i].protect);
            }
            left -= _waterFillWithdraw(bc, take, left);
        }

        /* Phase 2: всё, что ещё можно */
        if (left > 0) {
            for (uint256 i; i < n; ++i) {
                bc[i].active = (bc[i].amount > 0);
            }
            left -= _waterFillWithdraw(bc, take, left);
        }

        // require(left == 0, "Not enough grain to withdraw");
    }

    /*─────────────────────── INTERNALS ───────────────────────*/

    function _sumAmounts(BasketCache[] memory bc) private pure returns (uint256 s) {
        for (uint256 i; i < bc.length; ++i) {
            s += bc[i].amount;
        }
    }

    function _precompute(BasketCache[] memory bc, uint256 newTotal) private pure {
        for (uint256 i; i < bc.length; ++i) {
            /* ideal */
            if (bc[i].targetBps == 0 || bc[i].targetBps == BIPS) {
                bc[i].ideal = 0; // handled by later phases
            } else {
                uint256 wish = (newTotal * bc[i].targetBps) / BIPS;
                bc[i].ideal = wish > bc[i].capacity ? bc[i].capacity : wish;
            }

            /* protect */
            uint256 limBps = bc[i].protectBps == 0 ? bc[i].targetBps : bc[i].protectBps;
            uint256 lim = (newTotal * limBps) / BIPS;
            bc[i].protect = lim > bc[i].capacity ? bc[i].capacity : lim;
        }
    }

    /// deposit water-fill with ideal-cap
    function _waterFillDeposit(BasketCache[] memory bc, uint256[] memory out, uint256 want)
        private
        pure
        returns (uint256 done)
    {
        uint256 left = want;
        uint256 n = bc.length;

        while (left > 0) {
            uint256 act;
            for (uint256 i; i < n; ++i) {
                if (bc[i].active) ++act;
            }
            if (act == 0) break;

            uint256 per = left / act;
            if (per == 0) per = 1;

            for (uint256 i; i < n && left > 0; ++i) {
                if (bc[i].active) {
                    // ← добавили ограничение по ideal
                    uint256 need = (bc[i].ideal == 0 || bc[i].amount >= bc[i].ideal)
                        ? type(uint256).max
                        : bc[i].ideal - bc[i].amount;

                    uint256 room = bc[i].capacity - bc[i].amount;
                    uint256 use = room < per ? room : per;
                    if (use > need) use = need;
                    if (use > left) use = left;

                    bc[i].amount += use;
                    out[i] += use;
                    left -= use;

                    if (use == room || use == need) {
                        bc[i].active = false;
                    } // достигли capacity или ideal
                }
            }
        }
        done = want - left;
    }

    /* water-fill helpers: identical to previous version,
       just renamed for brevity */

    function _waterFillDepos11t(BasketCache[] memory bc, uint256[] memory out, uint256 want)
        private
        pure
        returns (uint256 done)
    {
        uint256 left = want;
        uint256 n = bc.length;

        while (left > 0) {
            uint256 act;
            for (uint256 i; i < n; ++i) {
                if (bc[i].active) ++act;
            }
            if (act == 0) break;

            uint256 per = left / act;
            if (per == 0) per = 1;

            for (uint256 i; i < n && left > 0; ++i) {
                if (bc[i].active) {
                    uint256 room = bc[i].capacity - bc[i].amount;
                    uint256 use = room < per ? room : per;
                    if (use > left) use = left;

                    bc[i].amount += use;
                    out[i] += use;
                    left -= use;

                    if (use == room) bc[i].active = false;
                }
            }
        }
        done = want - left;
    }

    /// withdraw water-fill with threshold floor
    function _waterFillWithdraw(BasketCache[] memory bc, uint256[] memory out, uint256 want)
        private
        pure
        returns (uint256 done)
    {
        uint256 left = want;
        uint256 n = bc.length;

        while (left > 0) {
            uint256 act;
            for (uint256 i; i < n; ++i) {
                if (bc[i].active) ++act;
            }
            if (act == 0) break;

            uint256 per = left / act;
            if (per == 0) per = 1;

            for (uint256 i; i < n && left > 0; ++i) {
                if (bc[i].active) {
                    // ← ограничение по threshold
                    uint256 excess = bc[i].amount > bc[i].protect ? bc[i].amount - bc[i].protect : bc[i].amount; // фаза-2: threshold == 0

                    uint256 take = excess < per ? excess : per;
                    if (take > left) take = left;

                    bc[i].amount -= take;
                    out[i] += take;
                    left -= take;

                    if (take == excess) {
                        bc[i].active = false;
                    } // ушли до threshold
                }
            }
        }
        done = want - left;
    }

    function _waterFillWithdraw1(BasketCache[] memory bc, uint256[] memory out, uint256 want)
        private
        pure
        returns (uint256 done)
    {
        uint256 left = want;
        uint256 n = bc.length;

        while (left > 0) {
            uint256 act;
            for (uint256 i; i < n; ++i) {
                if (bc[i].active) ++act;
            }
            if (act == 0) break;

            uint256 per = left / act;
            if (per == 0) per = 1;

            for (uint256 i; i < n && left > 0; ++i) {
                if (bc[i].active) {
                    uint256 avail = bc[i].amount;
                    uint256 take = avail < per ? avail : per;
                    if (take > left) take = left;

                    bc[i].amount -= take;
                    out[i] += take;
                    left -= take;

                    if (take == avail) bc[i].active = false;
                }
            }
        }
        done = want - left;
    }
}
