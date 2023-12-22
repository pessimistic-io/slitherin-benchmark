// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

interface IRewardTracker {
    function averageStakedAmounts(address _account)
        external
        view
        returns (uint256);

    function cumulativeRewards(address _account)
        external
        view
        returns (uint256);
}

