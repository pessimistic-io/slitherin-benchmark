// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

/**
 * @notice Level loyalty token. Mint to trader whenever they take a trade. Auto redeem to LVL when batch completed
 */
interface ILyLevel {
    /**
     * @notice accept reward send from IncentiveController
     */
    function addReward(uint256 _rewardAmount) external;

    /**
     * @notice finalize current batch, redeem (burn) all lyLVL to LVL
     */
    function allocate() external;

    function epochDuration() external view returns (uint256);
}

