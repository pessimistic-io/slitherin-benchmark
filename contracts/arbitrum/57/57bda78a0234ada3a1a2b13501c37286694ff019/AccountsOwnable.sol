// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { AccessControlInternal } from "./AccessControlInternal.sol";
import { AccountsInternal } from "./AccountsInternal.sol";

contract AccountsOwnable is AccessControlInternal {
    event CollectFees(uint256 timestamp, uint256 amount);

    function collectFees() external onlyRole(REVENUE_ROLE) {
        uint256 amount = AccountsInternal.getAccountBalance(address(this));
        AccountsInternal.withdraw(address(this), amount);
        emit CollectFees(block.timestamp, amount);
    }
}

