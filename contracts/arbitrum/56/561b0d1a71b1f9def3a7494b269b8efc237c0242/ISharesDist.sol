// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISharesDist {
    function getMinPrice() external view returns (uint256);
    function createShare(address account, uint256 amount) external;
    function getShareReward(address account, uint256 _creationTime) external view returns (uint256);
    function getAllSharesRewards(address account) external view returns (uint256);
    function cashoutShareReward(address account, uint256 _creationTime) external;
    function cashoutAllSharesRewards(address account) external;
    function compoundShareReward(address account, uint256 creationTime, uint256 rewardAmount) external;
}

