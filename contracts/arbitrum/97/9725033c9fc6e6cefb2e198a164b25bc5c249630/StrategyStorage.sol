// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "./Ownable.sol";

contract StrategyStorage is Ownable {
    //scaled up by ACC_EARNING_PRECISION
    uint256 public rewardTokensPerShare;
    uint256 internal constant ACC_EARNING_PRECISION = 1e18;

    //pending reward = (user.amount * rewardTokensPerShare) / ACC_EARNING_PRECISION - user.rewardDebt
    mapping(address => uint256) public rewardDebt;

    function increaseRewardDebt(
        address user,
        uint256 shareAmount
    ) external onlyOwner {
        rewardDebt[user] +=
            (rewardTokensPerShare * shareAmount) /
            ACC_EARNING_PRECISION;
    }

    function decreaseRewardDebt(
        address user,
        uint256 shareAmount
    ) external onlyOwner {
        rewardDebt[user] -=
            (rewardTokensPerShare * shareAmount) /
            ACC_EARNING_PRECISION;
    }

    function setRewardDebt(
        address user,
        uint256 userShares
    ) external onlyOwner {
        rewardDebt[user] =
            (rewardTokensPerShare * userShares) /
            ACC_EARNING_PRECISION;
    }

    function increaseRewardTokensPerShare(uint256 amount) external onlyOwner {
        rewardTokensPerShare += amount;
    }
}

