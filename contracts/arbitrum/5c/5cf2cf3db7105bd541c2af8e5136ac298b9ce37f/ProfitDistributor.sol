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

import "./IERC20.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";

contract ProfitDistributor is AccessControl {
    using SafeERC20 for IERC20;

    struct ProfitRecipient {
        address account;
        uint32 share;
    }

    IERC20 immutable USDC;
    ProfitRecipient[] public recipients;

    uint256 constant TOTAL_SHARE_SUM = 1e9;
    uint8 constant MAX_RECIPIENTS_COUNT = 20;

    constructor(IERC20 _USDC) {
        USDC = _USDC;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function distributeProfit() external {
        require(_checkRecipientsArray(recipients), "Wrong recipients list");

        uint256 amount = USDC.balanceOf(address(this));
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 transferAmount = (amount * recipients[i].share) /
                TOTAL_SHARE_SUM;
            if (transferAmount > 0)
                USDC.safeTransfer(recipients[i].account, transferAmount);
        }
    }

    function setProfitRecipients(ProfitRecipient[] calldata _recipients)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(_checkRecipientsArray(_recipients), "Wrong recipients list");
        delete recipients;

        for (uint256 i = 0; i < _recipients.length; i++) {
            recipients.push(_recipients[i]);
        }
    }

    function _checkRecipientsArray(ProfitRecipient[] memory _recipients)
        internal
        pure
        returns (bool)
    {
        uint256 summary = 0;

        if (_recipients.length > MAX_RECIPIENTS_COUNT) return false;
        for (uint256 i = 0; i < _recipients.length; i++) {
            summary += _recipients[i].share;
        }
        return summary == TOTAL_SHARE_SUM;
    }
}

