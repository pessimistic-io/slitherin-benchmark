// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ILSDepositaryFacet {
    function _initialize_LSDepositaryFacet() external;

    function stake(uint256 amount) external;

    function stakeFor(address staker, uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function exit() external;

    function updateReward(address account) external;
}

