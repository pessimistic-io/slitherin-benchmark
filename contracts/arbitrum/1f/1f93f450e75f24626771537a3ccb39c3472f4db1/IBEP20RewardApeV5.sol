// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IBEP20RewardApeV5 {
    function REWARD_TOKEN() external view returns (IERC20);

    function STAKE_TOKEN() external view returns (IERC20);

    function bonusEndBlock() external view returns (uint256);

    function owner() external view returns (address);

    function poolInfo()
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accRewardTokenPerShare
        );

    function renounceOwnership() external;

    function rewardPerBlock() external view returns (uint256);

    function startBlock() external view returns (uint256);

    function totalRewardsAllocated() external view returns (uint256);

    function totalRewardsPaid() external view returns (uint256);

    function totalStaked() external view returns (uint256);

    function transferOwnership(address newOwner) external;

    function userInfo(address)
        external
        view
        returns (uint256 amount, uint256 rewardDebt);

    function initialize(
        address _stakeToken,
        address _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock
    ) external;

    function getMultiplier(uint256 _from, uint256 _to)
        external
        view
        returns (uint256);

    function setBonusEndBlock(uint256 _bonusEndBlock) external;

    function pendingReward(address _user) external view returns (uint256);

    function updatePool() external;

    function deposit(uint256 _amount) external;

    function depositTo(uint256 _amount, address _user) external;

    function withdraw(uint256 _amount) external;

    function rewardBalance() external view returns (uint256);

    function getUnharvestedRewards() external view returns (uint256);

    function depositRewards(uint256 _amount) external;

    function totalStakeTokenBalance() external view returns (uint256);

    function getStakeTokenFeeBalance() external view returns (uint256);

    function setRewardPerBlock(uint256 _rewardPerBlock) external;

    function skimStakeTokenFees(address _to) external;

    function emergencyWithdraw() external;

    function emergencyRewardWithdraw(uint256 _amount) external;

    function sweepToken(address token) external;
}

