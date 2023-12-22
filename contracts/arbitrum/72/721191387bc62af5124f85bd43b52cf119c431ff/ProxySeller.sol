pragma solidity ^0.8.3;

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

import "./IOperationalTreasury.sol";
import "./IHegicStrategy.sol";
import "./SafeERC20.sol";

contract ProxySeller {
    using SafeERC20 for IERC20;

    event ReferralRegistered(address indexed referrer, uint256 indexed epoch, uint256 indexed position);

    IOperationalTreasury immutable operationalTreasury;
    IERC20 immutable token;

    constructor(IOperationalTreasury _operationalTreasury){
        operationalTreasury = _operationalTreasury;
        token = _operationalTreasury.token();
        token.safeApprove(address(operationalTreasury), type(uint256).max);
    }

    function buyWithReferal(
        IHegicStrategy strategy,
        uint256 amount,
        uint256 period,
        bytes[] calldata additional,
        address referrer
    ) external {
        (, uint256 positivePNL) = strategy.calculateNegativepnlAndPositivepnl(amount, period, additional);
        token.safeTransferFrom(msg.sender, address(this), positivePNL);
        uint256 epoch = operationalTreasury.coverPool().currentEpoch();
        uint256 position = operationalTreasury.manager().nextTokenId();
        operationalTreasury.buy(strategy, msg.sender, amount, period, additional);
        emit ReferralRegistered(referrer, epoch, position);
    }
}
