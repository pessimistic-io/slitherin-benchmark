// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRubicStaking {
    function enterStaking(uint256 _amount, uint128 _lockTime) external;

    function enterStakingTo(uint256 _amount, uint128 _lockTime, address _to) external;

    function unstake(uint256 tokenId) external;

    function claimRewards(uint256 tokenId) external returns (uint256 rewards);

    function addRewards() external payable;

    function calculateRewards(uint256 tokenId) external view returns (uint256 rewards);

    function setRate(uint256 rate) external;

    function setEmergencyStop(bool isStopped) external;

    event Enter(uint256 amount, uint128 lockTime, uint256 tokenId);
    event Unstake(uint256 amount, uint256 tokenId);
    event Migrate(uint256 amount, uint128 lockTime, uint256 tokenId);
    event Claim(uint256 amount, uint256 tokenId);
    event AddRewards(uint256 amount);
    event Rate(uint256 rate);
    event EmergencyStop(bool isStopped);
}

