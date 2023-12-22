// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";

import {IRewardsManager} from "./IRewardsManager.sol";

abstract contract RewardsManager is IRewardsManager, Ownable {

    address public rewardsToken;

    uint256 public rewardsAmount;

    constructor(address rewardsToken_, uint256 rewardsAmount_) {
        rewardsToken = rewardsToken_;
        rewardsAmount = rewardsAmount_;
    }

    function setRewardsToken(address rewardsToken_) external onlyOwner {
        rewardsToken = rewardsToken_;
    }

    function setRewardsAmount(uint256 rewardsAmount_) external onlyOwner {
        rewardsAmount = rewardsAmount_;
    }

    function withdrawRewards(address recipient_, uint256 amount_) external onlyOwner {
        IERC20(rewardsToken).transfer(recipient_, amount_);
    }

}

