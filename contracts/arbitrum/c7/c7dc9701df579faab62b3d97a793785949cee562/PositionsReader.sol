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
import "./IOperationalTreasury.sol";


interface StrategyV0 {
    struct StrategyData {
        uint128 amount;
        uint128 strike;
    }

    function strategyData(uint256 strategyID) external view returns (StrategyData memory);
}

struct PositionInfo {
    IOperationalTreasury.LockedLiquidityState state;
    IHegicStrategy strategy;
    address owner;
    uint128 negativepnl;
    uint128 positivepnl;
    uint32 expiration;
    bytes srategyData;
}

contract PositionsReader {
    IOperationalTreasury immutable opt;
    IPositionsManager manager;

    constructor (IOperationalTreasury _opt) {
        opt = _opt;
        manager = _opt.manager();
    }

    function getPositoinsInfo(uint256[] memory IDs) view external returns (PositionInfo[] memory infos) {
        infos = new PositionInfo[](IDs.length);
        for (uint i = 0; i < IDs.length; i++) {
            infos[i] = _positionInfo(IDs[i]);
        }
    }

    function _positionInfo(uint256 id) view internal returns(PositionInfo memory pi) {
        (pi.state, pi.strategy, pi.negativepnl, pi.positivepnl, pi.expiration) = opt.lockedLiquidity(id);
        pi.owner = manager.ownerOf(id);

        try pi.strategy.positionExpiration(id) returns (uint32 expiration) {
            pi.expiration = expiration;
        }catch{}

        try pi.strategy.version() returns (uint) {
            pi.srategyData = pi.strategy.strategyData(id);
        } catch {
            pi.srategyData = abi.encode(StrategyV0(address(pi.strategy)).strategyData(id));
        }
    }
}
