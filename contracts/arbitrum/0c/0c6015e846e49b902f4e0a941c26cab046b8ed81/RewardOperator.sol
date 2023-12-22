// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./console.sol";

interface IStakingPoolFactory {
    function addRewards(address stakingToken, uint256 rewardsAmount) external;
}

interface IMintableERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IRewardERC20 is IERC20 {
    function convert(uint256 amount) external;
}

contract RewardOperator is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IMintableERC20;
    using SafeERC20 for IRewardERC20;
    
    address public operator;
    address public originalToken;
    address public rewardsToken;
    address public stakingPoolFactory;

    event SetOperator(address indexed operator);

    modifier onlyOperator() {
        require(msg.sender == operator, "Allow only operator");
        _;
    }

    constructor (address _originalToken, address _rewardsToken, address _stakingPoolFactory) {
        originalToken = _originalToken;
        rewardsToken = _rewardsToken;
        stakingPoolFactory = _stakingPoolFactory;
    }

    function setOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "Operator need to be defined");

        operator = _operator;

        emit SetOperator(_operator);
    }

    function addRewards(address[] memory stakingTokens, uint256[] memory rewards) external onlyOperator nonReentrant {
        require(stakingTokens.length == rewards.length, "Length mismatch");

        // Calculate total reward amount
        uint256 totalReward;
        for (uint256 i = 0; i < rewards.length; i++) {
            totalReward = totalReward + rewards[i];
        }

        // Mint total original token
        IMintableERC20(originalToken).mint(address(this), totalReward);

        // Convert total original token to rewards tokens
        //  - Approve original token transferable to reward token
        if (IMintableERC20(originalToken).allowance(address(this), rewardsToken) < totalReward) {
            IMintableERC20(originalToken).approve(rewardsToken, (2**256 - 1));
        }
        //  - Convert original token to reward token
        IRewardERC20(rewardsToken).convert(totalReward);

        // Add rewards to staking pools
        //  - Approve reward token transferable for StakingPoolFactory
        if (IRewardERC20(rewardsToken).allowance(address(this), stakingPoolFactory) < totalReward) {
            IRewardERC20(rewardsToken).approve(stakingPoolFactory, (2**256 - 1));
        }
        //  - Add rewards to each pool
        for (uint256 i = 0; i < stakingTokens.length; i++) {
            IStakingPoolFactory(stakingPoolFactory).addRewards(stakingTokens[i], rewards[i]);
        }
    }
}
