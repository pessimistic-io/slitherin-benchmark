// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IAlpRewardHandler {
    function notifyRewardAmount(uint256 reward) external;

    function getReward(address account) external;

    function distributeRewards(uint256 _teamAmount, uint256 _waterAmount) external;

    function distributeCAKE(uint256 _amount) external;

    function getVodkaSplit(uint256 _amount) external view returns (uint256, uint256, uint256);

    function claimCAKERewards(address account) external;

    function setDebtRecordCAKE(address _account) external;
}
