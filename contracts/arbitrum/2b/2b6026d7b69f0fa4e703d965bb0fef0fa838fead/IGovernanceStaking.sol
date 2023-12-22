// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGovernanceStaking {
    function stake(uint256 _amount, uint256 _duration) external;
    function unstake(uint256 _amount) external;
    function claim() external;
    function distribute(address _token, uint256 _amount) external;
    function whitelistReward(address _rewardToken) external;
    function pending(address _user, address _token) external view returns (uint256);
    function userStaked(address _user) external view returns (uint256);
}
