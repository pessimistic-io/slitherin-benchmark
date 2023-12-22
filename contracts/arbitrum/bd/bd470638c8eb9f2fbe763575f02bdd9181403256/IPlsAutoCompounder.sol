// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPlsAutoCompounder {
    function stakePls(uint112 amount) external;

    function unStakePls() external;

    function claimPlsRewards() external;

    function calculatePendingRewards(address staker) external view returns (uint256);

    function updatePlsRewards() external;

    function stakeAllPls() external;

    function unStakeAllPls() external;

    function adminUnstakeAndClaimPlsAssetsAndBribes() external;

    function claimPlsAssets() external;

    function claimPlsBribes() external;

    function accumulatePls(bytes[] calldata swapData, address[] calldata tokens) external;
}

