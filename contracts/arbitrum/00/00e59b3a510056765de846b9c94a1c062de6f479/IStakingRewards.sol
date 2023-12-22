// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IStakingRewards {
    function accountVoteShare(address account) external view returns (uint256);
    function updateWeeklyRewards(uint256 newRewards) external;
    function getStLODEAmount(address _address) external view returns (uint256);
    function getStLodeLockTime(address _address) external view returns (uint256);
}
