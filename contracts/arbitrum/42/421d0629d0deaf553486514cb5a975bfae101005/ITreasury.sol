// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface ITreasury {
    function rewardReporter(uint256 _poolId, address _reporter) external;

    function premiumIncome(uint256 _poolId, uint256 _amount) external;
}

