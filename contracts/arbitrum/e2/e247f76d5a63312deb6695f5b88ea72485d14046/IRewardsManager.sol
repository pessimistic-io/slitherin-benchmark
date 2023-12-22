// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IRewardsManager {

    function rewardsToken() external returns (address);

    function setRewardsToken(address rewardsToken_) external;

    function rewardsAmount() external returns (uint256);

    function setRewardsAmount(uint256 rewardsAmount_) external;

    function withdrawRewards(address recipient_, uint256 amount_) external;

}

