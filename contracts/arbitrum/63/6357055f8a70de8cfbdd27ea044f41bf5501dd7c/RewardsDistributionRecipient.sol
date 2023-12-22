// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Inheritance
import "./Ownable.sol";

abstract contract RewardsDistributionRecipient is Ownable {
    address public rewardsDistribution;

    function notifyRewardAmount(uint digital, uint american, uint turbo) external virtual;

    modifier onlyRewardsDistribution() {
        require(
            msg.sender == rewardsDistribution,
            "Caller is not RewardsDistribution contract"
        );
        _;
    }

    function setRewardsDistribution(address _rewardsDistribution)
    external
    onlyOwner
    {
        rewardsDistribution = _rewardsDistribution;
    }
}

