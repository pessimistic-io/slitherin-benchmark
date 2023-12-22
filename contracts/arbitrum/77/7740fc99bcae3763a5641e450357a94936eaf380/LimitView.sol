pragma solidity ^0.8.3;
pragma experimental ABIEncoderV2;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import "./IHegicStrategy.sol";

contract LimitView {
    struct Limit {
        uint256 locked;
        uint256 limit;
        uint256 available;
        uint128 negativePNL;
        uint128 positivePNL;
    }

    function getLimitsFor(
        IHegicStrategy[] memory strategies,
        uint256 amount,
        uint32[] calldata period,
        bytes[] calldata additional
    ) external view returns (Limit[] memory) {
        Limit[] memory res = new Limit[](strategies.length);
        for (uint i = 0; i < strategies.length; i++) {
            IHegicStrategy strat = strategies[i];

            res[i].locked = strat.getLockedByStrategy();
            res[i].limit = strat.lockedLimit();

            try strat.getAvailableContracts(period[i], additional) returns (
                uint256 available
            ) {
                res[i].available = available;
            } catch {}

            try
                strat.calculateNegativepnlAndPositivepnl(
                    amount,
                    period[i],
                    additional
                )
            returns (uint128 negativePNL, uint128 positivePNL) {
                res[i].negativePNL = negativePNL;
                res[i].positivePNL = positivePNL;
            } catch {}
        }
        return res;
    }

    struct calculateLocalLimitsRequestItem {
        IHegicStrategy strategy;
        uint32 period;
        uint256 positionsAmount;
    }

    function calculateLocalLimits(
        calculateLocalLimitsRequestItem[] memory request
    ) external view returns (uint256[] memory result) {
        result = new uint256[](request.length);

        for (uint256 i = 0; i < request.length; i++) {
            uint256 locked = request[i].strategy.getLockedByStrategy();
            
            try request[i]
                .strategy
                .calculateNegativepnlAndPositivepnl(
                    request[i].positionsAmount,
                    request[i].period,
                    new bytes[](0)
                )
            returns (uint128 npnl, uint128) {
                result[i] = npnl + locked;
            } catch {
                result[i] = 0;
            }
        }
    }
}

