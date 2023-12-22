// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";

import {RewardsManager} from "./RewardsManager.sol";

import {IL2} from "./IL2.sol";

contract Treasury is RewardsManager {

    uint256 public mintRewardsAmount;

    constructor(address rewardsToken_) RewardsManager(rewardsToken_, 1000e18) {
        mintRewardsAmount = 10000e18;
    }

    function mintRewards() external onlyOwner {
        IL2(rewardsToken).mintToTreasury(mintRewardsAmount);
    }

    function setMintRewardsAmount(uint256 mintRewardsAmount_) external onlyOwner {
        mintRewardsAmount = mintRewardsAmount_;
    }

    function distributionRewards(address rewardPool_, uint256 amount_) external onlyOwner {
        require(rewardPool_ != address(0), "Treasury: reward pool is zero address");
        require(amount_ > 0, "Treasury: amount is zero");
        IERC20(rewardsToken).transfer(rewardPool_, amount_);
    }

}

