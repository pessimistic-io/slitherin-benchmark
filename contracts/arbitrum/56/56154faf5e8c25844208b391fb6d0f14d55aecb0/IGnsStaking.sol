// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGnsStaking {
    function stakeGns(uint128 amount) external;
    function unstakeGns(uint128 amount) external;
    function harvestDai() external;
    function stakers(address user) external view returns (uint128 stakedGns, uint128 debtDai);
    function pendingRewardDai(address user) external view returns (uint128 pending);
}

