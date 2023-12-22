// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IGlpRewardHandler {
    function notifyRewardAmount(uint256 reward) external;

    function getReward(address account) external;

    function distributeRewards(uint256 _teamAmount, uint256 _waterAmount) external;

    function distributeGlp(uint256 _amount) external;

    function getVodkaSplit(uint256 _amount) external view returns (uint256, uint256, uint256);

    function claimETHRewards(address account) external;

    function setDebtRecordWETH(address _account) external;

}

