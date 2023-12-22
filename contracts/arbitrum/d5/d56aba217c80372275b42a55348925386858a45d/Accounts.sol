// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { AccountsInternal } from "./AccountsInternal.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { IAccountsEvents } from "./IAccountsEvents.sol";

contract Accounts is ReentrancyGuard, IAccountsEvents {
    /* ========== VIEWS ========== */

    function getAccountBalance(address party) external view returns (uint256) {
        return AccountsInternal.getAccountBalance(party);
    }

    function getMarginBalance(address party) external view returns (uint256) {
        return AccountsInternal.getMarginBalance(party);
    }

    function getLockedMarginIsolated(address party, uint256 positionId) external view returns (uint256) {
        return AccountsInternal.getLockedMarginIsolated(party, positionId);
    }

    function getLockedMarginCross(address party) external view returns (uint256) {
        return AccountsInternal.getLockedMarginCross(party);
    }

    function getLockedMarginReserved(address party) external view returns (uint256) {
        return AccountsInternal.getLockedMarginReserved(party);
    }

    /* ========== WRITES ========== */

    function deposit(uint256 amount) external nonReentrant {
        AccountsInternal.deposit(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        AccountsInternal.withdraw(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function allocate(uint256 amount) external {
        AccountsInternal.allocate(msg.sender, amount);
        emit Allocate(msg.sender, amount);
    }

    function deallocate(uint256 amount) external {
        AccountsInternal.deallocate(msg.sender, amount);
        emit Deallocate(msg.sender, amount);
    }

    function depositAndAllocate(uint256 amount) external nonReentrant {
        AccountsInternal.deposit(msg.sender, amount);
        AccountsInternal.allocate(msg.sender, amount);

        emit Deposit(msg.sender, amount);
        emit Allocate(msg.sender, amount);
    }

    function deallocateAndWithdraw(uint256 amount) external nonReentrant {
        AccountsInternal.deallocate(msg.sender, amount);
        AccountsInternal.withdraw(msg.sender, amount);

        emit Deallocate(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

    function addFreeMarginIsolated(uint256 amount, uint256 positionId) external {
        AccountsInternal.addFreeMarginIsolated(msg.sender, amount, positionId);
        emit AddFreeMarginIsolated(msg.sender, amount, positionId);
    }

    function addFreeMarginCross(uint256 amount) external {
        AccountsInternal.addFreeMarginCross(msg.sender, amount);
        emit AddFreeMarginCross(msg.sender, amount);
    }

    function removeFreeMarginCross() external {
        uint256 removedAmount = AccountsInternal.removeFreeMarginCross(msg.sender);
        emit RemoveFreeMarginCross(msg.sender, removedAmount);
    }
}

