// SPDX-License-Identifier: MIT
pragma solidity ^0.5.16;

import "./Ownable.sol";

import "./Constants.sol";

contract MultipleRewardDistributionRecipient is Ownable, Constants  {

    mapping (address => bool) public rewardDistribution;

    function initialize(
        address[] memory _rewardDistributions
    )
    public
    initializer {
        // NotifyHelper
        rewardDistribution[msg.sender] = true;
        rewardDistribution[DEFAULT_MULTI_SIG_ADDRESS] = true;

        rewardDistribution[REWARD_FORWARDER] = true;

        for(uint256 i = 0; i < _rewardDistributions.length; i++) {
            rewardDistribution[_rewardDistributions[i]] = true;
        }
    }

    function notifyTargetRewardAmount(address rewardToken, uint256 reward) external;

    modifier onlyRewardDistribution() {
        require(rewardDistribution[msg.sender], "Caller is not reward distribution");
        _;
    }

    function setRewardDistribution(
        address[] calldata _newRewardDistribution,
        bool _flag
    )
    external
    onlyOwner
    {
        for(uint256 i = 0; i < _newRewardDistribution.length; i++){
            rewardDistribution[_newRewardDistribution[i]] = _flag;
        }
    }
}

