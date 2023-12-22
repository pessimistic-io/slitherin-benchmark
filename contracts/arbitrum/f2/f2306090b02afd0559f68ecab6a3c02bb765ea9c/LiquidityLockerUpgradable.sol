// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./LiquidityLocker.sol";

contract LiquidityLockerUpgradable is LiquidityLocker {
    
    function adjustWithdrawalAddresses() public virtual {
        _deleteWithdrawalAddresses();
        _deleteAdjustWithdrawalAddresses();
    }

    function _deleteLock(
        uint256 idx,
        address withdrawalAddress
    ) internal virtual override returns (bool) {
        require(hasLockEnded(idx), "The lock is not ended.");
        _deleteWithdrawalAddresses();
        locks[idx] = locks[locks.length - 1];
        locks.pop();
        _deleteAdjustWithdrawalAddresses();
        return true;
    }

    function _deleteAdjustWithdrawalAddresses() internal virtual {
         for (uint256 i = 0; i < locks.length; i++) {
            Lock memory lock = locks[i];
            locksOfWithdrawalAddress[lock.withdrawalAddress].push(i);
            withdrawalAddresses[lock.withdrawalAddress] = true;
        }
    }

    function _deleteWithdrawalAddresses() internal virtual {
        for (uint256 i = 0; i < locks.length; i++) {
            Lock memory lock = locks[i];
            delete locksOfWithdrawalAddress[lock.withdrawalAddress];
            withdrawalAddresses[lock.withdrawalAddress] = false;
        }
    }
}

