// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IHarvester {
    struct GlobalUserDeposit {
        uint256 globalDepositAmount;
        uint256 globalLockLpAmount;
        uint256 globalLpAmount;
        int256 globalRewardDebt;
    }

    function getUserGlobalDeposit(address user)
        external
        view
        returns (GlobalUserDeposit memory);
}

